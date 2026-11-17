#if DEBUG
protocol CleanupBenchmarkModelGenerating: TextGenerating {
    func isModelDownloaded(_ modelID: String) async -> Bool
    func load(modelID: String) async throws
    func unload() async
}
#endif
