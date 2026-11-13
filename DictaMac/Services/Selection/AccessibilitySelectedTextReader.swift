import AppKit
import ApplicationServices

@MainActor
final class AccessibilitySelectedTextReader: SelectedTextReading, SecureSelectionDetecting {
    typealias SelectionResult = (
        text: String?,
        screenRect: CGRect?,
        sourceBundleID: String?,
        isSecure: Bool
    )
    typealias SelectionQuery = @MainActor () -> SelectionResult?

    static let messagingTimeout: Float = 0.2

    private let permissionReader: any AccessibilityPermissionReading
    private let selectionQuery: SelectionQuery
    private(set) var didEncounterSecureField = false

    init(
        permissionReader: any AccessibilityPermissionReading,
        selectionQuery: @escaping SelectionQuery = AccessibilitySelectedTextReader.querySelection
    ) {
        self.permissionReader = permissionReader
        self.selectionQuery = selectionQuery
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
        guard let text = result.text else { return nil }
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
        copiedValue(attribute: attribute, from: element) as? String
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
