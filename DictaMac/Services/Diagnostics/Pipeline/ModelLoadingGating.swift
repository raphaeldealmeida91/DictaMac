protocol ModelLoadingGating: Sendable {
    var isLoading: Bool { get }

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value
}
