import Foundation

enum ProfileConstants {
    static let defaultBundleID = "default"
}

struct AppProfile: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    var bundleID: String
    var displayName: String
    var mappings: [MouseButton: Action]

    init(bundleID: String, displayName: String, mappings: [MouseButton: Action] = [:]) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.mappings = mappings
    }

    // Custom Codable because Dictionary keys must be String-convertible
    enum CodingKeys: String, CodingKey {
        case bundleID, displayName, mappings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        displayName = try container.decode(String.self, forKey: .displayName)
        let stringKeyedMappings = try container.decode([String: Action].self, forKey: .mappings)
        var result: [MouseButton: Action] = [:]
        for (key, value) in stringKeyedMappings {
            if let intKey = Int(key), let button = MouseButton(rawValue: intKey) {
                result[button] = value
            }
        }
        mappings = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(displayName, forKey: .displayName)
        let stringKeyedMappings = Dictionary(uniqueKeysWithValues: mappings.map { ("\($0.key.rawValue)", $0.value) })
        try container.encode(stringKeyedMappings, forKey: .mappings)
    }
}
