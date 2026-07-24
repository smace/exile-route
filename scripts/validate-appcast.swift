#!/usr/bin/env swift

import CryptoKit
import Foundation

struct AppcastValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw AppcastValidationError(message: message)
    }
}

func child(named localName: String, in element: XMLElement) -> XMLElement? {
    element.children?
        .compactMap { $0 as? XMLElement }
        .first { $0.localName == localName || $0.name == localName }
}

func attribute(named localName: String, in element: XMLElement) -> String? {
    element.attributes?
        .first { $0.localName == localName || $0.name == localName }?
        .stringValue
}

func trimmedText(named localName: String, in element: XMLElement) -> String? {
    child(named: localName, in: element)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: validate-appcast.swift APPCAST INFO_PLIST\n".utf8)
    )
    exit(64)
}

do {
    let appcastURL = URL(fileURLWithPath: arguments[1])
    let infoPlistURL = URL(fileURLWithPath: arguments[2])
    let signedFeedData = try Data(contentsOf: appcastURL)
    let infoPlistData = try Data(contentsOf: infoPlistURL)
    let infoPlist = try requireDictionary(
        PropertyListSerialization.propertyList(from: infoPlistData, options: [], format: nil)
    )

    guard let publicKeyString = infoPlist["SUPublicEDKey"] as? String,
          let publicKeyData = Data(base64Encoded: publicKeyString) else {
        throw AppcastValidationError(message: "SUPublicEDKey is missing or invalid.")
    }
    try require(publicKeyData.count == 32, "SUPublicEDKey must decode to 32 bytes.")
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)

    let signatureMarker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let markerRange = signedFeedData.range(of: signatureMarker, options: .backwards) else {
        throw AppcastValidationError(message: "The appcast is not signed.")
    }
    let feedContent = Data(signedFeedData[..<markerRange.lowerBound])
    let signatureBlockData = Data(signedFeedData[markerRange.lowerBound...])
    guard let signatureBlock = String(data: signatureBlockData, encoding: .utf8) else {
        throw AppcastValidationError(message: "The appcast signature block is not UTF-8.")
    }
    let signaturePattern = #"^<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]+={0,2})\nlength: ([0-9]+)\n-->\n?$"#
    let signatureExpression = try NSRegularExpression(pattern: signaturePattern)
    let signatureRange = NSRange(signatureBlock.startIndex..., in: signatureBlock)
    guard let signatureMatch = signatureExpression.firstMatch(
        in: signatureBlock,
        range: signatureRange
    ), signatureMatch.range == signatureRange,
    let encodedSignatureRange = Range(signatureMatch.range(at: 1), in: signatureBlock),
    let lengthRange = Range(signatureMatch.range(at: 2), in: signatureBlock),
    let signedLength = Int(signatureBlock[lengthRange]),
    let feedSignature = Data(base64Encoded: String(signatureBlock[encodedSignatureRange])) else {
        throw AppcastValidationError(message: "The appcast signature block is malformed.")
    }
    try require(feedSignature.count == 64, "The appcast signature must decode to 64 bytes.")
    try require(signedLength == feedContent.count, "The appcast signed length is incorrect.")
    try require(
        publicKey.isValidSignature(feedSignature, for: feedContent),
        "The appcast signature is invalid."
    )

    let document = try XMLDocument(
        data: feedContent,
        options: [.nodeLoadExternalEntitiesNever, .nodePreserveCDATA]
    )
    let itemNodes = try document.nodes(
        forXPath: "/*[local-name()='rss']/*[local-name()='channel']/*[local-name()='item']"
    )
    let items = try itemNodes.map { node -> XMLElement in
        guard let item = node as? XMLElement else {
            throw AppcastValidationError(message: "The appcast contains a non-element item.")
        }
        return item
    }
    try require(!items.isEmpty, "The appcast must contain at least one item.")

    var previousBuild: Int?
    var seenBuilds = Set<Int>()
    var validatedArchives = 0
    let semanticVersionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$"#

    for item in items {
        guard let buildString = trimmedText(named: "version", in: item),
              let build = Int(buildString),
              build > 0 else {
            throw AppcastValidationError(message: "Every appcast item needs a positive build number.")
        }
        try require(seenBuilds.insert(build).inserted, "Duplicate appcast build \(build).")
        if let previousBuild {
            try require(
                previousBuild > build,
                "Appcast builds must be ordered newest first."
            )
        }
        previousBuild = build

        guard let version = trimmedText(named: "shortVersionString", in: item),
              version.range(of: semanticVersionPattern, options: .regularExpression) != nil else {
            throw AppcastValidationError(
                message: "Build \(build) has an invalid semantic version."
            )
        }
        if let channel = trimmedText(named: "channel", in: item) {
            try require(channel == "beta", "Build \(build) uses unsupported channel \(channel).")
        }

        guard let enclosure = child(named: "enclosure", in: item),
              let urlString = attribute(named: "url", in: enclosure),
              let archiveURL = URL(string: urlString),
              let expectedLengthString = attribute(named: "length", in: enclosure),
              let expectedLength = Int64(expectedLengthString),
              let encodedSignature = attribute(named: "edSignature", in: enclosure),
              let archiveSignature = Data(base64Encoded: encodedSignature) else {
            throw AppcastValidationError(
                message: "Build \(build) has an incomplete enclosure."
            )
        }

        try require(archiveURL.scheme == "https", "Build \(build) does not use HTTPS.")
        try require(archiveURL.host == "github.com", "Build \(build) is not hosted on GitHub.")
        try require(
            archiveURL.path.hasPrefix("/smace/exile-route/releases/download/"),
            "Build \(build) points outside the Exile Route release path."
        )
        try require(
            archiveURL.lastPathComponent == "ExileRoute-\(version).zip",
            "Build \(build) archive name does not match version \(version)."
        )
        try require(expectedLength > 0, "Build \(build) has an invalid archive length.")
        try require(
            expectedLength <= 100 * 1_024 * 1_024,
            "Build \(build) exceeds the 100 MiB update limit."
        )
        try require(
            archiveSignature.count == 64,
            "Build \(build) archive signature must decode to 64 bytes."
        )

        let (downloadURL, response) = try await URLSession.shared.download(from: archiveURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppcastValidationError(message: "Build \(build) returned a non-HTTP response.")
        }
        try require(
            (200..<300).contains(httpResponse.statusCode),
            "Build \(build) download returned HTTP \(httpResponse.statusCode)."
        )
        try require(
            httpResponse.url?.scheme == "https",
            "Build \(build) download redirected outside HTTPS."
        )

        let resourceValues = try downloadURL.resourceValues(forKeys: [.fileSizeKey])
        let actualLength = Int64(resourceValues.fileSize ?? -1)
        try require(
            actualLength == expectedLength,
            "Build \(build) archive length is \(actualLength), expected \(expectedLength)."
        )
        let archiveData = try Data(contentsOf: downloadURL, options: .mappedIfSafe)
        try require(
            publicKey.isValidSignature(archiveSignature, for: archiveData),
            "Build \(build) archive signature is invalid."
        )
        validatedArchives += 1
    }

    print(
        "Validated signed appcast and \(validatedArchives) cryptographically verified archive(s)."
    )
} catch {
    FileHandle.standardError.write(Data("Appcast validation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}

func requireDictionary(_ value: Any) throws -> [String: Any] {
    guard let dictionary = value as? [String: Any] else {
        throw AppcastValidationError(message: "Info.plist is not a dictionary.")
    }
    return dictionary
}
