import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var statusText = "Ready"
}
