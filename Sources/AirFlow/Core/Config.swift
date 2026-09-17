import Foundation

/// Application-wide configuration loaded dynamically from environment or .env file.
public struct AppConfig: Sendable {
    public let targetPhoneName: String?
    public let targetPhoneUUID: String?
    public let targetPhoneBTAddr: String?
    
    public let targetHeadphoneName: String
    public let targetHeadphoneUUID: String?
    public let targetHeadphoneBTAddr: String?
    
    public let arbitrationCooldownMs: Int
    public let enableAirPodsBypass: Bool
    
    public init(
        targetPhoneName: String? = nil,
        targetPhoneUUID: String? = nil,
        targetPhoneBTAddr: String? = nil,
        targetHeadphoneName: String = "Shokz",
        targetHeadphoneUUID: String? = nil,
        targetHeadphoneBTAddr: String? = nil,
        arbitrationCooldownMs: Int = 1500,
        enableAirPodsBypass: Bool = true
    ) {
        self.targetPhoneName = targetPhoneName
        self.targetPhoneUUID = targetPhoneUUID
        self.targetPhoneBTAddr = targetPhoneBTAddr
        self.targetHeadphoneName = targetHeadphoneName
        self.targetHeadphoneUUID = targetHeadphoneUUID
        self.targetHeadphoneBTAddr = targetHeadphoneBTAddr
        self.arbitrationCooldownMs = arbitrationCooldownMs
        self.enableAirPodsBypass = enableAirPodsBypass
    }
    
    /// Loads configuration from environment variables, falling back to parsing a local .env file.
    public static func load() -> AppConfig {
        let envDict = loadDotEnv()
        
        func get(_ key: String) -> String? {
            if let val = ProcessInfo.processInfo.environment[key], !val.isEmpty {
                return val
            }
            return envDict[key]
        }
        
        let phoneName = get("TARGET_PHONE_NAME")
        let phoneUUID = get("TARGET_PHONE_UUID")
        let phoneAddr = get("TARGET_PHONE_BT_ADDR")
        
        let headphoneName = get("TARGET_HEADPHONE_NAME") ?? "Shokz"
        let headphoneUUID = get("TARGET_HEADPHONE_UUID")
        let headphoneAddr = get("TARGET_HEADPHONE_BT_ADDR")
        
        let cooldownMs = Int(get("ARBITRATION_COOLDOWN_MS") ?? "1500") ?? 1500
        let bypassAirPods = (get("ENABLE_AIRPODS_BYPASS") ?? "true").lowercased() == "true"
        
        return AppConfig(
            targetPhoneName: phoneName,
            targetPhoneUUID: phoneUUID,
            targetPhoneBTAddr: phoneAddr,
            targetHeadphoneName: headphoneName,
            targetHeadphoneUUID: headphoneUUID,
            targetHeadphoneBTAddr: headphoneAddr,
            arbitrationCooldownMs: cooldownMs,
            enableAirPodsBypass: bypassAirPods
        )
    }
    
    /// Parses KEY=VALUE lines from .env if present.
    private static func loadDotEnv() -> [String: String] {
        var results: [String: String] = [:]
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        let envPath = (currentDir as NSString).appendingPathComponent(".env")
        
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return results
        }
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var val = parts[1].trimmingCharacters(in: .whitespaces)
                if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                    val = String(val.dropFirst().dropLast())
                }
                results[key] = val
            }
        }
        return results
    }
}
