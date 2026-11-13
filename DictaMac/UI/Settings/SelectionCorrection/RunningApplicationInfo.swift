struct RunningApplicationInfo: Identifiable, Equatable, Sendable {
    let name: String
    let bundleID: String

    var id: String { bundleID }
}
