import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon's `RegisterEventHotKey`, which
/// works while other apps are focused and needs no Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private let signature: FourCharCode = 0x554C5457 // 'ULTW'

    private init() {}

    @discardableResult
    func register(id: UInt32, combo: KeyCombo, handler: @escaping () -> Void) -> Bool {
        ensureHandlerInstalled()
        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            carbonModifiers(from: combo),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs.removeValue(forKey: id)
        }
        handlers.removeValue(forKey: id)
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func ensureHandlerInstalled() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            nil,
            nil
        )
        handlerInstalled = (status == noErr)
    }

    private func carbonModifiers(from combo: KeyCombo) -> UInt32 {
        var result: UInt32 = 0
        if combo.modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if combo.modifiers.contains(.option) { result |= UInt32(optionKey) }
        if combo.modifiers.contains(.control) { result |= UInt32(controlKey) }
        if combo.modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

/// Top-level C callback (captures no context, so it bridges to a C function
/// pointer) that routes the pressed hotkey back to the shared center.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    DispatchQueue.main.async {
        HotKeyCenter.shared.fire(id: id)
    }
    return noErr
}
