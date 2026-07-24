import Combine
import Foundation
import Sparkle

@MainActor
final class ApplicationUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    let distributionFlavor: DistributionFlavor
    private(set) var channel: UpdateChannel
    private var controller: SPUStandardUpdaterController?
    private var hasStarted = false

    init(
        channel: UpdateChannel,
        distributionFlavor: DistributionFlavor = .current
    ) {
        self.channel = distributionFlavor == .beta ? .beta : channel
        self.distributionFlavor = distributionFlavor
        super.init()
        if distributionFlavor.updatesEnabled {
            controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
        }
    }

    var updatesEnabled: Bool { distributionFlavor.updatesEnabled }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    func start() {
        guard updatesEnabled, !hasStarted else { return }
        hasStarted = true
        controller?.startUpdater()
    }

    func checkForUpdates() {
        guard updatesEnabled else { return }
        controller?.checkForUpdates(nil)
    }

    func selectChannel(_ channel: UpdateChannel) {
        guard self.channel != channel else { return }
        self.channel = channel
        controller?.updater.resetUpdateCycle()
        objectWillChange.send()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.allowedSparkleChannels
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["EXILE_ROUTE_UPDATE_FEED_URL"]
    }
}
