import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.obsidian.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("EXILE ROUTE")
                    .font(Theme.titleFont(size: 28))
                    .foregroundStyle(Theme.agedGold)
                Text("Configuration will appear here once the overlay is running.")
                    .foregroundStyle(Theme.ivory)
            }
            .padding(32)
        }
        .preferredColorScheme(.dark)
    }
}
