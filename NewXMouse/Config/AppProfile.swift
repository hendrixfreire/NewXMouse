import Foundation

enum ProfileConstants {
    static let defaultBundleID = "default"
}

struct MappingEntry: Codable, Equatable {
    var action: Action
    var enabled: Bool = true

    init(action: Action, enabled: Bool = true) {
        self.action = action
        self.enabled = enabled
    }
}

// MARK: - Layer

struct Layer: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var mappings: [MouseButton: MappingEntry]
    var isDefault: Bool

    init(id: UUID = UUID(), name: String, mappings: [MouseButton: MappingEntry] = [:], isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.mappings = mappings
        self.isDefault = isDefault
    }

    // Custom Codable because Dictionary keys must be String-convertible
    enum CodingKeys: String, CodingKey {
        case id, name, mappings, isDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false

        // Decode mappings — try MappingEntry first, then legacy Action format
        if let stringKeyedMappings = try? container.decode([String: MappingEntry].self, forKey: .mappings) {
            var result: [MouseButton: MappingEntry] = [:]
            for (key, value) in stringKeyedMappings {
                if let intKey = Int(key), let button = MouseButton(rawValue: intKey) {
                    result[button] = value
                }
            }
            mappings = result
        } else {
            let stringKeyedMappings = try container.decode([String: Action].self, forKey: .mappings)
            var result: [MouseButton: MappingEntry] = [:]
            for (key, value) in stringKeyedMappings {
                if let intKey = Int(key), let button = MouseButton(rawValue: intKey) {
                    result[button] = MappingEntry(action: value)
                }
            }
            mappings = result
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isDefault, forKey: .isDefault)
        let stringKeyedMappings = Dictionary(uniqueKeysWithValues: mappings.map { ("\($0.key.rawValue)", $0.value) })
        try container.encode(stringKeyedMappings, forKey: .mappings)
    }
}

// MARK: - AppProfile

struct AppProfile: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    var bundleID: String
    var displayName: String
    var layers: [Layer]
    var activeLayerID: UUID

    // Computed: mappings of the active layer (for backward compat & convenience)
    var mappings: [MouseButton: MappingEntry] {
        get { activeLayer?.mappings ?? [:] }
        set {
            if let idx = layers.firstIndex(where: { $0.id == activeLayerID }) {
                layers[idx].mappings = newValue
            }
        }
    }

    var activeLayer: Layer? {
        layers.first { $0.id == activeLayerID }
    }

    init(bundleID: String, displayName: String, layers: [Layer]? = nil) {
        self.bundleID = bundleID
        self.displayName = displayName
        if let layers {
            self.layers = layers
        } else {
            // Create a single default layer
            let defaultLayer = Layer(name: "Default", isDefault: true)
            self.layers = [defaultLayer]
        }
        self.activeLayerID = self.layers.first?.id ?? UUID()
    }

    // Legacy init — creates a single layer from a flat mappings dict
    init(bundleID: String, displayName: String, mappings: [MouseButton: MappingEntry]) {
        self.bundleID = bundleID
        self.displayName = displayName
        let defaultLayer = Layer(name: "Default", mappings: mappings, isDefault: true)
        self.layers = [defaultLayer]
        self.activeLayerID = defaultLayer.id
    }

    // Convenience init with plain Action dict (enabled by default)
    init(bundleID: String, displayName: String, actionMappings: [MouseButton: Action]) {
        self.bundleID = bundleID
        self.displayName = displayName
        let defaultLayer = Layer(name: "Default", mappings: actionMappings.mapValues { MappingEntry(action: $0) }, isDefault: true)
        self.layers = [defaultLayer]
        self.activeLayerID = defaultLayer.id
    }

    mutating func addLayer(name: String) {
        let newLayer = Layer(name: name)
        layers.append(newLayer)
    }

    mutating func removeLayer(id: UUID) {
        // Never remove the default layer
        guard let layer = layers.first(where: { $0.id == id }), !layer.isDefault else { return }
        layers.removeAll { $0.id == id }
        if activeLayerID == id {
            activeLayerID = layers.first?.id ?? UUID()
        }
    }

    mutating func switchToLayer(id: UUID) {
        guard layers.contains(where: { $0.id == id }) else { return }
        activeLayerID = id
    }

    mutating func renameLayer(id: UUID, name: String) {
        if let idx = layers.firstIndex(where: { $0.id == id }) {
            layers[idx].name = name
        }
    }

    // Custom Codable
    enum CodingKeys: String, CodingKey {
        case bundleID, displayName, layers, activeLayerID, mappings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        bundleID = try container.decode(String.self, forKey: .bundleID)
        displayName = try container.decode(String.self, forKey: .displayName)

        // Decode layers — may not exist in legacy config
        if let decodedLayers = try? container.decode([Layer].self, forKey: .layers) {
            layers = decodedLayers
            activeLayerID = try container.decode(UUID.self, forKey: .activeLayerID)
        } else {
            // Legacy format: flat mappings, no layers
            // Decode flat mappings
            var flatMappings: [MouseButton: MappingEntry] = [:]
            if let stringKeyedMappings = try? container.decode([String: MappingEntry].self, forKey: .mappings) {
                for (key, value) in stringKeyedMappings {
                    if let intKey = Int(key), let button = MouseButton(rawValue: intKey) {
                        flatMappings[button] = value
                    }
                }
            } else if let stringKeyedMappings = try? container.decode([String: Action].self, forKey: .mappings) {
                for (key, value) in stringKeyedMappings {
                    if let intKey = Int(key), let button = MouseButton(rawValue: intKey) {
                        flatMappings[button] = MappingEntry(action: value)
                    }
                }
            }

            let defaultLayer = Layer(name: "Default", mappings: flatMappings, isDefault: true)
            layers = [defaultLayer]
            activeLayerID = defaultLayer.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(layers, forKey: .layers)
        try container.encode(activeLayerID, forKey: .activeLayerID)
        // Encode active layer's mappings as top-level "mappings" for backward compat
        let activeMappings = activeLayer?.mappings ?? [:]
        let stringKeyedMappings = Dictionary(uniqueKeysWithValues: activeMappings.map { ("\($0.key.rawValue)", $0.value) })
        try container.encode(stringKeyedMappings, forKey: .mappings)
    }
}
