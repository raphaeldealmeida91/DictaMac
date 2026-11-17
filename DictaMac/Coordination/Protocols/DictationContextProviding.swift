@MainActor
protocol DictationContextProviding: AnyObject {
    func currentContext() -> DictationContext
}
