import AppKit
import ApplicationServices

@MainActor
final class AccessibilitySelectedTextReader: SelectedTextReading, SecureSelectionDetecting, FocusedTextReading {
    typealias SelectionResult = (
        text: String?,
        screenRect: CGRect?,
        sourceBundleID: String?,
        isSecure: Bool
    )
    typealias SelectionQuery = @MainActor () -> SelectionResult?
    typealias FocusedTextQuery = @MainActor () -> FocusedTextSnapshot?

    static let messagingTimeout: Float = 0.2
    static let focusedTextRadius = 5_000

    private let permissionReader: any AccessibilityPermissionReading
    private let selectionQuery: SelectionQuery
    private let focusedTextQuery: FocusedTextQuery
    private(set) var didEncounterSecureField = false

    init(
        permissionReader: any AccessibilityPermissionReading,
        selectionQuery: @escaping SelectionQuery = AccessibilitySelectedTextReader.querySelection,
        focusedTextQuery: @escaping FocusedTextQuery = AccessibilitySelectedTextReader.queryFocusedText
    ) {
        self.permissionReader = permissionReader
        self.selectionQuery = selectionQuery
        self.focusedTextQuery = focusedTextQuery
    }

    func readFocusedText() -> FocusedTextSnapshot? {
        guard permissionReader.isAccessibilityAuthorized else { return nil }
        return focusedTextQuery()
    }

    func readSelection() -> SelectionSnapshot? {
        didEncounterSecureField = false
        guard permissionReader.isAccessibilityAuthorized,
              let result = selectionQuery() else {
            return nil
        }
        guard !result.isSecure else {
            didEncounterSecureField = true
            return nil
        }
        guard let text = result.text, !text.isEmpty else { return nil }
        return SelectionSnapshot(
            text: text,
            screenRect: result.screenRect,
            sourceBundleID: result.sourceBundleID,
            isSecure: false
        )
    }

    private static func querySelection() -> SelectionResult? {
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, messagingTimeout)
        guard let focusedElement = copiedElement(
            attribute: kAXFocusedUIElementAttribute,
            from: systemElement
        ) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(focusedElement, messagingTimeout)
        return makeResult(from: focusedElement)
    }

    private static func queryFocusedText() -> FocusedTextSnapshot? {
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, messagingTimeout)
        guard let focusedElement = copiedElement(
            attribute: kAXFocusedUIElementAttribute,
            from: systemElement
        ) else { return nil }
        AXUIElementSetMessagingTimeout(focusedElement, messagingTimeout)
        let sourceBundleID = sourceBundleID(for: focusedElement)
        let subrole = copiedString(attribute: kAXSubroleAttribute, from: focusedElement)
        guard subrole != kAXSecureTextFieldSubrole as String else {
            return FocusedTextSnapshot(text: "", sourceBundleID: sourceBundleID, isSecure: true)
        }
        guard let text = copiedString(attribute: kAXValueAttribute, from: focusedElement),
              !text.isEmpty else { return nil }
        return FocusedTextSnapshot(
            text: focusedExcerpt(text, from: focusedElement),
            sourceBundleID: sourceBundleID,
            isSecure: false
        )
    }

    private static func focusedExcerpt(_ text: String, from element: AXUIElement) -> String {
        let value = text as NSString
        guard let range = copiedRange(attribute: kAXSelectedTextRangeAttribute, from: element) else {
            return value.substring(to: min(value.length, focusedTextRadius * 2))
        }
        let lowerBound = max(0, range.location - focusedTextRadius)
        let upperBound = min(value.length, NSMaxRange(range) + focusedTextRadius)
        return value.substring(with: NSRange(location: lowerBound, length: upperBound - lowerBound))
    }

    private static func makeResult(from element: AXUIElement) -> SelectionResult {
        let subrole = copiedString(attribute: kAXSubroleAttribute, from: element)
        let secureSubrole = kAXSecureTextFieldSubrole as String
        let sourceBundleID = sourceBundleID(for: element)
        guard subrole != secureSubrole else {
            return (nil, nil, sourceBundleID, true)
        }
        let text = copiedString(attribute: kAXSelectedTextAttribute, from: element)
        let range = copiedValue(attribute: kAXSelectedTextRangeAttribute, from: element)
        return (text, selectionBounds(for: range, element: element), sourceBundleID, false)
    }

    private static func copiedElement(attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = copiedValue(attribute: attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func copiedString(attribute: String, from element: AXUIElement) -> String? {
        let value = copiedValue(attribute: attribute, from: element)
        if let string = value as? String { return string }
        return (value as? NSAttributedString)?.string
    }

    private static func copiedRange(attribute: String, from element: AXUIElement) -> NSRange? {
        guard let value = copiedValue(attribute: attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func copiedValue(attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private static func selectionBounds(for range: CFTypeRef?, element: AXUIElement) -> CGRect? {
        guard let range else { return nil }
        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        )
        guard result == .success, let boundsValue else { return nil }
        return cgRect(from: boundsValue)
    }

    private static func cgRect(from value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
    }

    private static func sourceBundleID(for element: AXUIElement) -> String? {
        var processID = pid_t()
        guard AXUIElementGetPid(element, &processID) == .success else { return nil }
        return NSRunningApplication(processIdentifier: processID)?.bundleIdentifier
    }
}
