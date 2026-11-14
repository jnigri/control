import Carbon

// Global shortcuts, through the Carbon hot key API. It needs no extra permission,
// and macOS swallows the key, so the focused app never sees it.

private var actions: [UInt32: () -> Void] = [:]

/// Run `action` when Option + key (or Option + Shift + key) is pressed.
func bind(_ key: String, shift: Bool = false, _ action: @escaping () -> Void) {
    let id = UInt32(actions.count + 1)
    actions[id] = action
    let modifiers = optionKey | (shift ? shiftKey : 0)
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(keyCodes[key]!), UInt32(modifiers), EventHotKeyID(signature: 0, id: id),
                        GetEventDispatcherTarget(), 0, &ref)
}

/// Install one handler for all shortcuts. It looks up the action by the shortcut's id.
func listenForKeys() {
    var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        actions[id.id]?()
        return noErr
    }, 1, &pressed, nil, nil)
}

/// Key codes name physical keys, by their place on a U.S. keyboard.
private let keyCodes: [String: Int] = [
    "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
    "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E,
    "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J,
    "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
    "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
    "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y,
    "Z": kVK_ANSI_Z, "Tab": kVK_Tab, "Minus": kVK_ANSI_Minus, "Equal": kVK_ANSI_Equal, "Space": kVK_Space,
]
