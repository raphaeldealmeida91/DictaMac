@MainActor
protocol RunningApplicationProviding {
    func applications() -> [RunningApplicationInfo]
}
