struct FnGestureStateMachine: Sendable {
    enum Transition: Sendable, Equatable {
        case none
        case began
        case ended(published: Bool)
    }

    private(set) var isDown = false
    private(set) var pressWasPublished = false

    mutating func transition(isDown: Bool) -> Transition {
        guard isDown != self.isDown else { return .none }
        self.isDown = isDown
        if isDown { return .began }
        let published = pressWasPublished
        pressWasPublished = false
        return .ended(published: published)
    }

    mutating func publishIfValid() -> Bool {
        guard isDown, !pressWasPublished else { return false }
        pressWasPublished = true
        return true
    }

    mutating func reset() -> Bool {
        defer {
            isDown = false
            pressWasPublished = false
        }
        return pressWasPublished
    }
}
