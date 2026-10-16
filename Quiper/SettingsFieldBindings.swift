import Foundation

// MARK: - Persisted settings field bindings

/// One row per simply-mapped persisted setting: a `Settings` property that
/// round-trips a `PersistedSettings` field of the same value type without any
/// per-path transform. The disk-load, save, import, reset, and export paths
/// all iterate the row list, so a field's live key path, persisted key path,
/// and default live in exactly one place. Fields whose value or treatment
/// diverges between paths (services, hotkey, zoom levels, tab state, the
/// engine-shortcut toggle, version stamps, …) stay in explicit composite
/// sections beside the loops. Adding a plain persisted setting means one
/// `@Published` declaration, one `PersistedSettings` field + coding key, and
/// one row in `Settings.simplePersistedFields`.
/// Rows run against `Settings`, which is `@MainActor`; isolating the rows the
/// same way lets them take live `Settings` state as `inout`, which Swift 6
/// otherwise refuses across an isolation boundary.
@MainActor
struct SettingsFieldBinding<Value: Equatable> {
    let live: ReferenceWritableKeyPath<Settings, Value>
    let persisted: WritableKeyPath<PersistedSettings, Value?>
    /// Value assigned when the persisted key is absent. Matches the
    /// `@Published` initializer and the historic `??` fallbacks at every
    /// consumer, keeping decode-compatibility with files written before the
    /// setting existed.
    let defaultValue: Value
    /// The disk-load path historically skipped assigning fields whose decoded
    /// value equals the current one, so notification-posting `didSet`s do not
    /// fire for no-op loads. Rows whose historic assignment was always
    /// unconditional keep this false.
    let deduplicatesOnLoad: Bool
    /// Per-path inclusion flags expressing each row's historic treatment.
    /// Three fields diverge deliberately: `dockVisibility` is never assigned
    /// by reset(), `dragAreaPosition` is never written by export payloads,
    /// and `hasDismissedEngineSettingsShortcutNotice` participates in neither.
    let includedInExport: Bool
    let includedInReset: Bool

    init(
        live: ReferenceWritableKeyPath<Settings, Value>,
        persisted: WritableKeyPath<PersistedSettings, Value?>,
        defaultValue: Value,
        deduplicatesOnLoad: Bool = true,
        includedInExport: Bool = true,
        includedInReset: Bool = true
    ) {
        self.live = live
        self.persisted = persisted
        self.defaultValue = defaultValue
        self.deduplicatesOnLoad = deduplicatesOnLoad
        self.includedInExport = includedInExport
        self.includedInReset = includedInReset
    }

    func encode(from source: Settings, into target: inout PersistedSettings) {
        target[keyPath: persisted] = source[keyPath: live]
    }

    func decode(from source: PersistedSettings, into target: Settings) {
        target[keyPath: live] = source[keyPath: persisted] ?? defaultValue
    }

    /// Decode flavor used by the disk-load path only, applying the guarded
    /// assignment described in `deduplicatesOnLoad`.
    func decodeForLoad(from source: PersistedSettings, into target: Settings) {
        let value = source[keyPath: persisted] ?? defaultValue
        if !deduplicatesOnLoad || target[keyPath: live] != value {
            target[keyPath: live] = value
        }
    }

    func reset(into target: Settings) {
        target[keyPath: live] = defaultValue
    }
}

extension SettingsFieldBinding where Value == Bool {
    /// Convenience for boolean settings persisted as optional booleans. Their
    /// historic load-path assignments were unconditional, so deduplication
    /// stays off unless the row opts in.
    static func flag(
        _ live: ReferenceWritableKeyPath<Settings, Bool>,
        _ persisted: WritableKeyPath<PersistedSettings, Bool?>,
        _ defaultValue: Bool,
        deduplicatesOnLoad: Bool = false,
        includedInExport: Bool = true,
        includedInReset: Bool = true
    ) -> SettingsFieldBinding<Bool> {
        Self(
            live: live,
            persisted: persisted,
            defaultValue: defaultValue,
            deduplicatesOnLoad: deduplicatesOnLoad,
            includedInExport: includedInExport,
            includedInReset: includedInReset
        )
    }
}

extension SettingsFieldBinding where Value: RawRepresentable, Value.RawValue == String {
    /// Convenience for string-raw-value enum settings, which historically
    /// deduplicate on the load path to avoid re-broadcasting equal UI state.
    static func enumDefault(
        _ live: ReferenceWritableKeyPath<Settings, Value>,
        _ persisted: WritableKeyPath<PersistedSettings, Value?>,
        _ defaultValue: Value,
        deduplicatesOnLoad: Bool = true,
        includedInExport: Bool = true,
        includedInReset: Bool = true
    ) -> SettingsFieldBinding<Value> {
        Self(
            live: live,
            persisted: persisted,
            defaultValue: defaultValue,
            deduplicatesOnLoad: deduplicatesOnLoad,
            includedInExport: includedInExport,
            includedInReset: includedInReset
        )
    }
}

/// Optional-valued setting whose persisted absence maps to a nil live value
/// (no default substitution). Decode assigns the raw optional exactly like
/// the historic `= persisted.x` form.
@MainActor
struct OptionalSettingsFieldBinding<Value: Equatable> {
    let live: ReferenceWritableKeyPath<Settings, Value?>
    let persisted: WritableKeyPath<PersistedSettings, Value?>

    func encode(from source: Settings, into target: inout PersistedSettings) {
        target[keyPath: persisted] = source[keyPath: live]
    }

    func decode(from source: PersistedSettings, into target: Settings) {
        target[keyPath: live] = source[keyPath: persisted]
    }

    func decodeForLoad(from source: PersistedSettings, into target: Settings) {
        decode(from: source, into: target)
    }

    func reset(into target: Settings) {
        target[keyPath: live] = nil
    }
}

/// Type-erased wrapper so rows of differing value types share one list.
@MainActor
struct AnySettingsFieldBinding {
    private let encodeBlock: (Settings, inout PersistedSettings) -> Void
    private let decodeBlock: (PersistedSettings, Settings) -> Void
    private let decodeForLoadBlock: (PersistedSettings, Settings) -> Void
    private let resetBlock: (Settings) -> Void
    /// See `SettingsFieldBinding.includedInExport` / `includedInReset`.
    let includedInExport: Bool
    let includedInReset: Bool

    init<Value: Equatable>(_ binding: SettingsFieldBinding<Value>) {
        encodeBlock = { binding.encode(from: $0, into: &$1) }
        decodeBlock = { binding.decode(from: $0, into: $1) }
        decodeForLoadBlock = { binding.decodeForLoad(from: $0, into: $1) }
        resetBlock = { binding.reset(into: $0) }
        includedInExport = binding.includedInExport
        includedInReset = binding.includedInReset
    }

    /// Convenience for rows that are almost uniform but have one tailored
    /// operation (for example deriving the alternate-modifier key from the
    /// shortcut bindings struct). Both closures take `(source, destination)`
    /// in that order.
    init(
        encode: @escaping (Settings, inout PersistedSettings) -> Void,
        decode: @escaping (PersistedSettings, Settings) -> Void,
        reset: @escaping (Settings) -> Void
    ) {
        encodeBlock = encode
        decodeBlock = decode
        decodeForLoadBlock = decode
        resetBlock = reset
        includedInExport = true
        includedInReset = true
    }

    init<Value: Equatable>(_ binding: OptionalSettingsFieldBinding<Value>) {
        encodeBlock = { binding.encode(from: $0, into: &$1) }
        decodeBlock = { binding.decode(from: $0, into: $1) }
        decodeForLoadBlock = { binding.decodeForLoad(from: $0, into: $1) }
        resetBlock = { binding.reset(into: $0) }
        includedInExport = true
        includedInReset = true
    }

    func encode(from source: Settings, into target: inout PersistedSettings) {
        encodeBlock(source, &target)
    }

    func decode(from source: PersistedSettings, into target: Settings) {
        decodeBlock(source, target)
    }

    func decodeForLoad(from source: PersistedSettings, into target: Settings) {
        decodeForLoadBlock(source, target)
    }

    func reset(into target: Settings) {
        resetBlock(target)
    }
}

// MARK: - Path loops

extension Settings {
    /// Writes every simple field from the live properties into a payload.
    /// Template/export payloads pass `forExport: true`, which skips the rows
    /// that are deliberately absent from those artifacts.
    func populateSimplePersistedFields(
        into target: inout PersistedSettings,
        forExport: Bool
    ) {
        for field in Self.simplePersistedFields
        where !forExport || field.includedInExport {
            field.encode(from: self, into: &target)
        }
    }

    /// Reads the simple fields back into the live properties using the
    /// history-preserving guarded assignments of the disk-load path.
    func applySimplePersistedFieldsForLoad(from source: PersistedSettings) {
        for field in Self.simplePersistedFields {
            field.decodeForLoad(from: source, into: self)
        }
    }

    /// Reads the simple fields back into the live properties with
    /// unconditional assignment, matching the import path's semantics.
    func applySimplePersistedFields(from source: PersistedSettings) {
        for field in Self.simplePersistedFields {
            field.decode(from: source, into: self)
        }
    }

    /// Restores the simple fields to their defaults. Reset() keeps the noted
    /// exclusions untouched rather than defaulting them.
    func resetSimplePersistedFields() {
        for field in Self.simplePersistedFields
        where field.includedInReset {
            field.reset(into: self)
        }
    }
}

// MARK: - Binding rows

/// Posting-row order matches the historic assignment order of the disk-load
/// and import paths, keeping the published-notification sequence stable. The
/// no-post rows interleaved between them are unobservable — their stores are
/// save-gated and trigger no side effects.
extension Settings {
    static let simplePersistedFields: [AnySettingsFieldBinding] = [
        .init(SettingsFieldBinding(
            live: \.updatePreferences,
            persisted: \.updatePreferences,
            defaultValue: UpdatePreferences(),
            deduplicatesOnLoad: false
        )),
        .init(SettingsFieldBinding(
            live: \.appShortcutBindings,
            persisted: \.appShortcuts,
            defaultValue: .defaults,
            deduplicatesOnLoad: false
        )),
        // Derived sibling key of the shortcut bindings struct; decode restores
        // it after the bindings row so the explicit value (when present)
        // wins over the struct's own copy.
        .init(
            encode: { source, target in
                target.sessionDigitsAlternateModifiers = source.appShortcutBindings.sessionDigitsAlternateModifiers
            },
            decode: { source, target in
                if let altModifiers = source.sessionDigitsAlternateModifiers {
                    target.appShortcutBindings.sessionDigitsAlternateModifiers = altModifiers
                }
            },
            reset: { _ in
                // Covered by resetting the whole shortcut bindings struct.
            }
        ),
        .init(.enumDefault(\.dockVisibility, \.dockVisibility, .whenVisible, includedInReset: false)),
        .init(.enumDefault(\.engineSelectorDisplayMode, \.engineSelectorDisplayMode, .auto)),
        .init(.enumDefault(\.sessionSelectorDisplayMode, \.sessionSelectorDisplayMode, .auto)),
        .init(.enumDefault(\.topBarVisibility, \.topBarVisibility, .visible)),
        // Historic export payloads deliberately omit this key, so restores on
        // other devices fall back to the default position.
        .init(.enumDefault(\.dragAreaPosition, \.dragAreaPosition, .top, includedInExport: false)),
        .init(.flag(\.showHiddenBarOnModifiers, \.showHiddenBarOnModifiers, true, deduplicatesOnLoad: true)),
        .init(.enumDefault(\.sessionModifierHoldBehavior, \.sessionModifierHoldBehavior, .expand)),
        .init(.enumDefault(\.engineModifierHoldBehavior, \.engineModifierHoldBehavior, .expand)),
        .init(SettingsFieldBinding(
            live: \.windowAppearance,
            persisted: \.windowAppearance,
            defaultValue: .default
        )),
        .init(.enumDefault(\.colorScheme, \.colorScheme, .system)),
        .init(.enumDefault(\.settingsColorStyle, \.settingsColorStyle, .colorful)),
        .init(.flag(\.automaticallySwitchEngineOnLastSessionClose, \.automaticallySwitchEngineOnLastSessionClose, true)),
        .init(.flag(\.autoCreateSessionOnEmptyEngineActivation, \.autoCreateSessionOnEmptyEngineActivation, true)),
        .init(.flag(\.shouldPurgeDanglingWebData, \.shouldPurgeDanglingWebData, true)),
        .init(.flag(\.hasCompletedGhostOnboarding, \.hasCompletedGhostOnboarding, false)),
        .init(.flag(
            \.hasDismissedEngineSettingsShortcutNotice,
            \.hasDismissedEngineSettingsShortcutNotice,
            false,
            includedInExport: false,
            includedInReset: false
        )),
        .init(.flag(\.enableHUDDoubleTapCmd, \.enableHUDDoubleTapCmd, true)),
        .init(.flag(\.enableHUDCmdEscape, \.enableHUDCmdEscape, true)),
        .init(.flag(\.showOnAllSpaces, \.showOnAllSpaces, false)),
        .init(.flag(\.keepOverlayOnTop, \.keepOverlayOnTop, true)),
        .init(.flag(\.hideOnFocusLoss, \.hideOnFocusLoss, false)),
        .init(.flag(\.focusLossEffectEnabled, \.focusLossEffectEnabled, true)),
        .init(.enumDefault(\.tabSurvivalPolicy, \.tabSurvivalPolicy, .always, deduplicatesOnLoad: false)),
        .init(.flag(\.enablePromptHistory, \.enablePromptHistory, true)),
        .init(.enumDefault(\.promptRecordingIndicatorStyle, \.promptRecordingIndicatorStyle, .dashed, deduplicatesOnLoad: false)),
        .init(.flag(\.promptHistoryRecordOnSubmit, \.promptHistoryRecordOnSubmit, true)),
        .init(.flag(\.promptHistoryRecordOnCmdBackspace, \.promptHistoryRecordOnCmdBackspace, true)),
        .init(.flag(\.promptHistoryRecordOnSelectionClear, \.promptHistoryRecordOnSelectionClear, false)),
        .init(SettingsFieldBinding(
            live: \.tabNavigationRingSize,
            persisted: \.tabNavigationRingSize,
            defaultValue: 2,
            deduplicatesOnLoad: false
        )),
        .init(.flag(\.globalEngineDigitShortcutsEnabled, \.globalEngineDigitShortcutsEnabled, false)),
        .init(.flag(\.askWhereToSaveDownloads, \.askWhereToSaveDownloads, false)),
        .init(.flag(\.blockAdsAndTrackers, \.blockAdsAndTrackers, true)),
        .init(OptionalSettingsFieldBinding(
            live: \.defaultBrowserFallbackBundleIdentifier,
            persisted: \.defaultBrowserFallbackBundleIdentifier
        )),
    ]
}
