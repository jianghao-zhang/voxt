import XCTest
import AppKit
import Carbon
import IOKit.hidsystem
@testable import Voxt

@MainActor
final class HotkeySupportTests: XCTestCase {
    func testLoadCanonicalizesStoredFunctionModifierHotkey() {
        let defaults = UserDefaults.standard
        let keyCodeKey = AppPreferenceKey.hotkeyKeyCode
        let modifiersKey = AppPreferenceKey.hotkeyModifiers
        let sidedModifiersKey = AppPreferenceKey.hotkeySidedModifiers
        let savedKeyCode = defaults.object(forKey: keyCodeKey)
        let savedModifiers = defaults.object(forKey: modifiersKey)
        let savedSidedModifiers = defaults.object(forKey: sidedModifiersKey)
        defer {
            restoreDefaultsValue(savedKeyCode, forKey: keyCodeKey)
            restoreDefaultsValue(savedModifiers, forKey: modifiersKey)
            restoreDefaultsValue(savedSidedModifiers, forKey: sidedModifiersKey)
        }

        defaults.set(Int(UInt16(kVK_Function)), forKey: keyCodeKey)
        defaults.set(Int(NSEvent.ModifierFlags.function.rawValue), forKey: modifiersKey)
        defaults.set(0, forKey: sidedModifiersKey)

        XCTAssertEqual(
            HotkeyPreference.load(),
            HotkeyPreference.Hotkey(
                keyCode: HotkeyPreference.modifierOnlyKeyCode,
                modifiers: [.function],
                sidedModifiers: []
            )
        )
    }

    func testLoadCanonicalizesStoredRightCommandModifierHotkey() {
        let defaults = UserDefaults.standard
        let keyCodeKey = AppPreferenceKey.hotkeyKeyCode
        let modifiersKey = AppPreferenceKey.hotkeyModifiers
        let sidedModifiersKey = AppPreferenceKey.hotkeySidedModifiers
        let savedKeyCode = defaults.object(forKey: keyCodeKey)
        let savedModifiers = defaults.object(forKey: modifiersKey)
        let savedSidedModifiers = defaults.object(forKey: sidedModifiersKey)
        defer {
            restoreDefaultsValue(savedKeyCode, forKey: keyCodeKey)
            restoreDefaultsValue(savedModifiers, forKey: modifiersKey)
            restoreDefaultsValue(savedSidedModifiers, forKey: sidedModifiersKey)
        }

        defaults.set(Int(UInt16(kVK_RightCommand)), forKey: keyCodeKey)
        defaults.set(Int(NSEvent.ModifierFlags.command.rawValue), forKey: modifiersKey)
        defaults.set(0, forKey: sidedModifiersKey)

        XCTAssertEqual(
            HotkeyPreference.load(),
            HotkeyPreference.Hotkey(
                keyCode: HotkeyPreference.modifierOnlyKeyCode,
                modifiers: [.command],
                sidedModifiers: [.rightCommand]
            )
        )
    }

    func testLoadCustomPasteResolvesToPresetValueWhenPresetIsCommandCombo() {
        let defaults = UserDefaults.standard
        let presetKey = AppPreferenceKey.hotkeyPreset
        let keyCodeKey = AppPreferenceKey.customPasteHotkeyKeyCode
        let modifiersKey = AppPreferenceKey.customPasteHotkeyModifiers
        let sidedModifiersKey = AppPreferenceKey.customPasteHotkeySidedModifiers
        let distinguishSidesKey = AppPreferenceKey.hotkeyDistinguishModifierSides
        let savedPreset = defaults.object(forKey: presetKey)
        let savedKeyCode = defaults.object(forKey: keyCodeKey)
        let savedModifiers = defaults.object(forKey: modifiersKey)
        let savedSidedModifiers = defaults.object(forKey: sidedModifiersKey)
        let savedDistinguishSides = defaults.object(forKey: distinguishSidesKey)
        defer {
            restoreDefaultsValue(savedPreset, forKey: presetKey)
            restoreDefaultsValue(savedKeyCode, forKey: keyCodeKey)
            restoreDefaultsValue(savedModifiers, forKey: modifiersKey)
            restoreDefaultsValue(savedSidedModifiers, forKey: sidedModifiersKey)
            restoreDefaultsValue(savedDistinguishSides, forKey: distinguishSidesKey)
        }

        defaults.set(HotkeyPreference.Preset.commandCombo.rawValue, forKey: presetKey)
        defaults.set(Int(UInt16(kVK_ANSI_V)), forKey: keyCodeKey)
        defaults.set(Int(NSEvent.ModifierFlags([.control, .command]).rawValue), forKey: modifiersKey)
        defaults.set(0, forKey: sidedModifiersKey)
        defaults.set(false, forKey: distinguishSidesKey)

        XCTAssertEqual(
            HotkeyPreference.loadCustomPaste(),
            HotkeyPreference.Hotkey(
                keyCode: UInt16(kVK_ANSI_V),
                modifiers: [.control, .command],
                sidedModifiers: []
            )
        )
        XCTAssertTrue(HotkeyPreference.loadDistinguishModifierSides())
    }

    func testMigrateDefaultsSyncsStoredCommandPresetHotkeys() {
        let defaults = UserDefaults.standard
        let presetKey = AppPreferenceKey.hotkeyPreset
        let keyCodeKey = AppPreferenceKey.customPasteHotkeyKeyCode
        let modifiersKey = AppPreferenceKey.customPasteHotkeyModifiers
        let sidedModifiersKey = AppPreferenceKey.customPasteHotkeySidedModifiers
        let distinguishSidesKey = AppPreferenceKey.hotkeyDistinguishModifierSides
        let transcriptionKeyCodeKey = AppPreferenceKey.hotkeyKeyCode
        let transcriptionModifiersKey = AppPreferenceKey.hotkeyModifiers
        let transcriptionSidedKey = AppPreferenceKey.hotkeySidedModifiers
        let savedPreset = defaults.object(forKey: presetKey)
        let savedKeyCode = defaults.object(forKey: keyCodeKey)
        let savedModifiers = defaults.object(forKey: modifiersKey)
        let savedSidedModifiers = defaults.object(forKey: sidedModifiersKey)
        let savedDistinguishSides = defaults.object(forKey: distinguishSidesKey)
        let savedTranscriptionKeyCode = defaults.object(forKey: transcriptionKeyCodeKey)
        let savedTranscriptionModifiers = defaults.object(forKey: transcriptionModifiersKey)
        let savedTranscriptionSided = defaults.object(forKey: transcriptionSidedKey)
        defer {
            restoreDefaultsValue(savedPreset, forKey: presetKey)
            restoreDefaultsValue(savedKeyCode, forKey: keyCodeKey)
            restoreDefaultsValue(savedModifiers, forKey: modifiersKey)
            restoreDefaultsValue(savedSidedModifiers, forKey: sidedModifiersKey)
            restoreDefaultsValue(savedDistinguishSides, forKey: distinguishSidesKey)
            restoreDefaultsValue(savedTranscriptionKeyCode, forKey: transcriptionKeyCodeKey)
            restoreDefaultsValue(savedTranscriptionModifiers, forKey: transcriptionModifiersKey)
            restoreDefaultsValue(savedTranscriptionSided, forKey: transcriptionSidedKey)
        }

        defaults.set(HotkeyPreference.Preset.commandCombo.rawValue, forKey: presetKey)
        defaults.set(Int(UInt16(kVK_ANSI_V)), forKey: keyCodeKey)
        defaults.set(Int(NSEvent.ModifierFlags([.control, .command]).rawValue), forKey: modifiersKey)
        defaults.set(0, forKey: sidedModifiersKey)
        defaults.set(false, forKey: distinguishSidesKey)
        defaults.set(Int(HotkeyPreference.modifierOnlyKeyCode), forKey: transcriptionKeyCodeKey)
        defaults.set(Int(NSEvent.ModifierFlags.command.rawValue), forKey: transcriptionModifiersKey)
        defaults.set(0, forKey: transcriptionSidedKey)

        HotkeyPreference.migrateDefaultsIfNeeded()

        XCTAssertEqual(defaults.integer(forKey: keyCodeKey), Int(UInt16(kVK_ANSI_V)))
        XCTAssertEqual(
            defaults.integer(forKey: modifiersKey),
            Int(NSEvent.ModifierFlags([.control, .command]).rawValue)
        )
        XCTAssertEqual(defaults.integer(forKey: sidedModifiersKey), 0)
        XCTAssertTrue(defaults.bool(forKey: distinguishSidesKey))
        XCTAssertEqual(defaults.integer(forKey: transcriptionSidedKey), SidedModifierFlags.rightCommand.rawValue)
    }

    func testLoadCustomPasteClearsSidedModifiersForChordHotkeys() {
        let defaults = UserDefaults.standard
        let presetKey = AppPreferenceKey.hotkeyPreset
        let keyCodeKey = AppPreferenceKey.customPasteHotkeyKeyCode
        let modifiersKey = AppPreferenceKey.customPasteHotkeyModifiers
        let sidedModifiersKey = AppPreferenceKey.customPasteHotkeySidedModifiers
        let savedPreset = defaults.object(forKey: presetKey)
        let savedKeyCode = defaults.object(forKey: keyCodeKey)
        let savedModifiers = defaults.object(forKey: modifiersKey)
        let savedSidedModifiers = defaults.object(forKey: sidedModifiersKey)
        defer {
            restoreDefaultsValue(savedPreset, forKey: presetKey)
            restoreDefaultsValue(savedKeyCode, forKey: keyCodeKey)
            restoreDefaultsValue(savedModifiers, forKey: modifiersKey)
            restoreDefaultsValue(savedSidedModifiers, forKey: sidedModifiersKey)
        }

        defaults.set(HotkeyPreference.Preset.custom.rawValue, forKey: presetKey)
        defaults.set(Int(UInt16(kVK_ANSI_L)), forKey: keyCodeKey)
        defaults.set(Int(NSEvent.ModifierFlags.command.rawValue), forKey: modifiersKey)
        defaults.set(SidedModifierFlags.leftCommand.rawValue, forKey: sidedModifiersKey)

        XCTAssertEqual(
            HotkeyPreference.loadCustomPaste(),
            HotkeyPreference.Hotkey(
                keyCode: UInt16(kVK_ANSI_L),
                modifiers: [.command],
                sidedModifiers: []
            )
        )
    }

    func testUpdatingKeepsModifierSetWhenDuplicatePressEventArrives() {
        let afterFirstPress = SidedModifierFlags.updating(
            from: [],
            keyCode: UInt16(kVK_RightShift),
            isPressed: true
        )
        let afterDuplicatePress = SidedModifierFlags.updating(
            from: afterFirstPress,
            keyCode: UInt16(kVK_RightShift),
            isPressed: true
        )

        XCTAssertEqual(afterDuplicatePress, [.rightShift])
    }

    func testUpdatingClearsModifierWhenDuplicateReleaseEventArrives() {
        let afterRelease = SidedModifierFlags.updating(
            from: [.rightShift],
            keyCode: UInt16(kVK_RightShift),
            isPressed: false
        )
        let afterDuplicateRelease = SidedModifierFlags.updating(
            from: afterRelease,
            keyCode: UInt16(kVK_RightShift),
            isPressed: false
        )

        XCTAssertEqual(afterDuplicateRelease, [])
    }

    func testUpdatingClearsOnlyReleasedSideWhenOppositeSideStaysDown() {
        let updated = SidedModifierFlags.updating(
            from: [.leftShift, .rightShift],
            keyCode: UInt16(kVK_Shift),
            isPressed: false
        )

        XCTAssertEqual(updated, [.rightShift])
    }

    func testFilteredDropsSidedModifiersWhenBaseModifierIsMissing() {
        let filtered = SidedModifierFlags([.rightShift, .rightCommand]).filtered(by: [.command])

        XCTAssertEqual(filtered, [.rightCommand])
    }

    func testHotkeyMatchesRequiresMatchingSideWhenDistinguishingEnabled() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.rightShift]
        )

        XCTAssertTrue(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskShift],
                sidedModifiers: [.rightShift],
                distinguishModifierSides: true
            )
        )
        XCTAssertFalse(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskShift],
                sidedModifiers: [.leftShift],
                distinguishModifierSides: true
            )
        )
    }

    func testHotkeyMatchesIgnoresSideWhenDistinguishingDisabled() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.rightShift]
        )

        XCTAssertTrue(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskShift],
                sidedModifiers: [.leftShift],
                distinguishModifierSides: false
            )
        )
    }

    func testHotkeyMatchesAllowsAdditionalSidedModifiersWhenRequiredSideIsPresent() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.command, .shift],
            sidedModifiers: [.rightCommand, .rightShift]
        )

        XCTAssertTrue(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskCommand, .maskShift],
                sidedModifiers: [.leftShift, .rightShift, .rightCommand],
                distinguishModifierSides: true
            )
        )
    }

    func testHotkeyMatchesRequiresMatchingSideForCustomNonModifierHotkey() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: [.option],
            sidedModifiers: [.rightOption]
        )

        XCTAssertTrue(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskAlternate],
                sidedModifiers: [.rightOption],
                distinguishModifierSides: true
            )
        )
        XCTAssertFalse(
            HotkeyPreference.hotkeyMatches(
                hotkey,
                eventFlags: [.maskAlternate],
                sidedModifiers: [.leftOption],
                distinguishModifierSides: true
            )
        )
    }

    func testSidedModifierFlagsFromEventFlagsParsesDeviceSpecificBits() {
        let flags = CGEventFlags(rawValue: UInt64(NX_COMMANDMASK | NX_DEVICERCMDKEYMASK | NX_DEVICERSHIFTKEYMASK))

        XCTAssertEqual(
            SidedModifierFlags.from(eventFlags: flags),
            [.rightCommand, .rightShift]
        )
    }

    func testDisplayStringShowsRightShiftWhenSideIsAvailable() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.rightShift]
        )

        XCTAssertEqual(
            HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: true),
            AppLocalization.format("Right %@", AppLocalization.localizedString("Shift"))
        )
    }

    func testDisplayStringFallsBackToGenericShiftWhenBothSidesArePresent() {
        let hotkey = HotkeyPreference.Hotkey(
            keyCode: HotkeyPreference.modifierOnlyKeyCode,
            modifiers: [.shift],
            sidedModifiers: [.leftShift, .rightShift]
        )

        XCTAssertEqual(
            HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: true),
            "Shift"
        )
    }

    private func restoreDefaultsValue(_ value: Any?, forKey key: String) {
        let defaults = UserDefaults.standard
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
