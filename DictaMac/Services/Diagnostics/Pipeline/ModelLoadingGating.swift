protocol ModelLoadingGating: Sendable {
    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value
}
