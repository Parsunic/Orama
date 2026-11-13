import AppKit
import GlanceCore

/// Everything the menu bar lets you change, saved in UserDefaults. API keys are
/// NOT here: they live in the macOS Keychain (see Keychain.swift).
///
/// Service fields (address, model, thinking) are saved per service, so
/// switching between services never loses what you typed for another one.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard
    private var loadingService = false

    @Published var presetID: String {
        didSet {
            defaults.set(presetID, forKey: Key.preset)
            loadService()
        }
    }
    @Published var baseURL: String = "" { didSet { saveService() } }
    @Published var model: String = "" { didSet { saveService() } }
    @Published var reasoningEffort: String = "" { didSet { saveService() } }
    @Published var backupModel: String = "" { didSet { saveService() } }

    @Published var instructions: String { didSet { defaults.set(instructions, forKey: Key.instructions) } }
    @Published var cloudTimeout: Double { didSet { defaults.set(cloudTimeout, forKey: Key.timeout) } }
    @Published var imageLongEdge: Int { didSet { defaults.set(imageLongEdge, forKey: Key.imageLongEdge) } }
    @Published var snapToText: Bool { didSet { defaults.set(snapToText, forKey: Key.snapToText) } }
    @Published var showDot: Bool { didSet { defaults.set(showDot, forKey: Key.showDot) } }
    @Published var showWorking: Bool { didSet { defaults.set(showWorking, forKey: Key.showWorking) } }
    @Published var dotOpacity: Double { didSet { defaults.set(dotOpacity, forKey: Key.dotOpacity) } }
    @Published var dotSize: Double { didSet { defaults.set(dotSize, forKey: Key.dotSize) } }
    @Published var corner: Corner { didSet { defaults.set(corner.rawValue, forKey: Key.corner) } }
    @Published var captureCombo: KeyCombo { didSet { saveCombo(captureCombo, Key.captureCombo) } }
    @Published var toggleCombo: KeyCombo { didSet { saveCombo(toggleCombo, Key.toggleCombo) } }

    /// Which services have a key saved, so the menu does not read the Keychain on every redraw.
    @Published private(set) var savedKeyIDs: Set<String> = []

    init() {
        // A local copy: `self` can't be read until every property has a value.
        let d = UserDefaults.standard
        presetID = d.string(forKey: Key.preset) ?? ServicePresets.defaultID
        instructions = d.string(forKey: Key.instructions) ?? Prompt.defaultInstructions
        cloudTimeout = d.object(forKey: Key.timeout) as? Double ?? 12
        imageLongEdge = d.object(forKey: Key.imageLongEdge) as? Int ?? 1280
        snapToText = d.object(forKey: Key.snapToText) as? Bool ?? true
        showDot = d.object(forKey: Key.showDot) as? Bool ?? true
        showWorking = d.object(forKey: Key.showWorking) as? Bool ?? true
        dotOpacity = d.object(forKey: Key.dotOpacity) as? Double ?? 0.12
        dotSize = d.object(forKey: Key.dotSize) as? Double ?? 44
        corner = Corner(rawValue: d.string(forKey: Key.corner) ?? "") ?? .bottomRight
        captureCombo = Self.loadCombo(Key.captureCombo, defaults: d) ?? .defaultCapture
        toggleCombo = Self.loadCombo(Key.toggleCombo, defaults: d) ?? .defaultToggle
        savedKeyIDs = Set(ServicePresets.all.map(\.id).filter { Keychain.read(account: $0) != nil })
        loadService()
    }

    var preset: ServicePreset { ServicePresets.preset(id: presetID) }

    var serviceConfig: ServiceConfig {
        ServiceConfig(format: preset.format, baseURL: baseURL, model: model, reasoningEffort: reasoningEffort, backupModel: backupModel)
    }

    /// The saved config for any service, not just the selected one (used by "Compare all").
    func serviceConfig(for id: String) -> ServiceConfig {
        let preset = ServicePresets.preset(id: id)
        return ServiceConfig(
            format: preset.format,
            baseURL: defaults.string(forKey: Key.service(id, "baseURL")) ?? preset.baseURL,
            model: defaults.string(forKey: Key.service(id, "model")) ?? preset.model,
            reasoningEffort: defaults.string(forKey: Key.service(id, "effort")) ?? preset.reasoningEffort,
            backupModel: defaults.string(forKey: Key.service(id, "backupModel")) ?? preset.backupModel
        )
    }

    func resetService() {
        for field in ["baseURL", "model", "effort", "backupModel"] {
            defaults.removeObject(forKey: Key.service(presetID, field))
        }
        loadService()
    }

    /// With "Increase contrast" on in Accessibility settings, the dot is never fainter than 25%.
    var effectiveDotOpacity: Double {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? max(dotOpacity, 0.25) : dotOpacity
    }

    // MARK: API keys

    func apiKey(for id: String) -> String {
        Keychain.read(account: id) ?? ""
    }

    func hasKey(_ id: String) -> Bool {
        savedKeyIDs.contains(id)
    }

    func saveAPIKey(_ key: String, for id: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.write(trimmed, account: id)
        if trimmed.isEmpty { savedKeyIDs.remove(id) } else { savedKeyIDs.insert(id) }
    }

    // MARK: Private

    private func loadService() {
        loadingService = true
        defer { loadingService = false }
        let config = serviceConfig(for: presetID)
        baseURL = config.baseURL
        model = config.model
        reasoningEffort = config.reasoningEffort
        backupModel = config.backupModel
    }

    private func saveService() {
        guard !loadingService else { return }
        defaults.set(baseURL, forKey: Key.service(presetID, "baseURL"))
        defaults.set(model, forKey: Key.service(presetID, "model"))
        defaults.set(reasoningEffort, forKey: Key.service(presetID, "effort"))
        defaults.set(backupModel, forKey: Key.service(presetID, "backupModel"))
    }

    private func saveCombo(_ combo: KeyCombo, _ key: String) {
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadCombo(_ key: String, defaults: UserDefaults) -> KeyCombo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    private enum Key {
        static let preset = "presetID"
        static let instructions = "instructions"
        static let timeout = "cloudTimeout"
        static let imageLongEdge = "imageLongEdge"
        static let snapToText = "snapToText"
        static let showDot = "showDot"
        static let showWorking = "showWorking"
        static let dotOpacity = "dotOpacity"
        static let dotSize = "dotSize"
        static let corner = "corner"
        static let captureCombo = "captureCombo"
        static let toggleCombo = "toggleCombo"

        static func service(_ id: String, _ field: String) -> String { "service.\(id).\(field)" }
    }
}
