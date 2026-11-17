import AppKit
import ApplicationServices
import OSLog

@MainActor
final class AccessibilityDictationContextProvider: DictationContextProviding {
    typealias ApplicationSnapshot = (bundleID: String?, name: String?)
    typealias ApplicationQuery = @MainActor () -> ApplicationSnapshot
    typealias PrecedingTextQuery = @MainActor (Float) -> String?

    static let messagingTimeout: Float = 0.15

    private let permissionReader: any AccessibilityPermissionReading
    private let applicationQuery: ApplicationQuery
    private let precedingTextQuery: PrecedingTextQuery
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "DictationContext"
    )

    init(
        permissionReader: any AccessibilityPermissionReading,
        applicationQuery: @escaping ApplicationQuery = AccessibilityDictationContextProvider.frontmostApplication,
        precedingTextQuery: @escaping PrecedingTextQuery = AccessibilityDictationContextProvider.queryPrecedingText
    ) {
        self.permissionReader = permissionReader
        self.applicationQuery = applicationQuery
        self.precedingTextQuery = precedingTextQuery
    }

    func currentContext() -> DictationContext {
        let application = applicationQuery()
        let text = permissionReader.isAccessibilityAuthorized
            ? precedingTextQuery(Self.messagingTimeout) ?? ""
            : ""
        let context = DictationContext(
            bundleID: application.bundleID,
            applicationName: application.name,
            precedingText: text
        )
        logger.info(
            "context captured category=\(context.category.rawValue, privacy: .public) preceding_length=\(context.precedingText.count)"
        )
        return context
    }

    private static func frontmostApplication() -> ApplicationSnapshot {
        let application = NSWorkspace.shared.frontmostApplication
        return (application?.bundleIdentifier, application?.localizedName)
    }

    private static func queryPrecedingText(timeout: Float) -> String? {
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, timeout)
        guard let focusedElement = copiedElement(
            attribute: kAXFocusedUIElementAttribute,
            from: systemElement
        ) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(focusedElement, timeout)
        guard !isSecure(focusedElement),
              let range = selectedTextRange(from: focusedElement),
              range.location > 0 else {
            return nil
        }
        return parameterizedText(before: range.location, from: focusedElement)
            ?? valueText(before: range.location, from: focusedElement)
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        copiedString(attribute: kAXSubroleAttribute, from: element)
            == kAXSecureTextFieldSubrole as String
    }

    private static func selectedTextRange(from element: AXUIElement) -> CFRange? {
        guard let value = copiedValue(
            attribute: kAXSelectedTextRangeAttribute,
            from: element
        ), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private static func parameterizedText(
        before cursorLocation: Int,
        from element: AXUIElement
    ) -> String? {
        let length = min(cursorLocation, DictationContext.maximumPrecedingCharacterCount)
        var range = CFRange(location: cursorLocation - length, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard result == .success, let value else { return nil }
        return string(from: value)
    }

    private static func valueText(
        before cursorLocation: Int,
        from element: AXUIElement
    ) -> String? {
        guard let value = copiedValue(attribute: kAXValueAttribute, from: element),
              let text = string(from: value) else {
            return nil
        }
        let utf16Text = text as NSString
        let location = min(cursorLocation, utf16Text.length)
        return utf16Text.substring(to: location)
    }

    private static func copiedElement(
        attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copiedValue(attribute: attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func copiedString(
        attribute: String,
        from element: AXUIElement
    ) -> String? {
        guard let value = copiedValue(attribute: attribute, from: element) else { return nil }
        return string(from: value)
    }

    private static func copiedValue(
        attribute: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private static func string(from value: CFTypeRef) -> String? {
        if let string = value as? String { return string }
        return (value as? NSAttributedString)?.string
    }
}
