import Combine

@MainActor
final class AppActivityModel: ObservableObject {
    @Published private(set) var state: DictationState = .idle

    func update(_ state: DictationState) {
        self.state = state
    }
}
