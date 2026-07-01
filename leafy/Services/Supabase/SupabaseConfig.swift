import Foundation

nonisolated enum SupabaseConfigError: LocalizedError {
    case missingURL
    case missingPublishableKey

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "缺少 SUPABASE_URL，请先在 Xcode Build Settings 或 xcconfig 里配置。"
        case .missingPublishableKey:
            return "缺少 SUPABASE_PUBLISHABLE_KEY，请先在 Xcode Build Settings 或 xcconfig 里配置。"
        }
    }
}

nonisolated struct SupabaseConfig {
    let url: URL
    let publishableKey: String
    let bootstrapFunctionName: String
    let feedFunctionName: String
    let weatherFunctionName: String
    let campusAIFunctionName: String
    let edgeRegion: String
    let communityAPIBaseURL: URL?

    static func load(from bundle: Bundle = .main) throws -> SupabaseConfig {
        let rawURL = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_URL"))
        let rawKey = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY"))
        let bootstrapFunctionName = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_COMMUNITY_BOOTSTRAP_FUNCTION"))
        let feedFunctionName = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_COMMUNITY_FEED_FUNCTION"))
        let weatherFunctionName = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_WEATHER_FUNCTION"))
        let campusAIFunctionName = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_CAMPUS_AI_FUNCTION"))
        let edgeRegion = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_COMMUNITY_EDGE_REGION"))
        let rawCommunityAPIBaseURL = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_COMMUNITY_API_BASE_URL"))

        guard !rawURL.isEmpty, let url = URL(string: rawURL) else {
            throw SupabaseConfigError.missingURL
        }

        guard !rawKey.isEmpty else {
            throw SupabaseConfigError.missingPublishableKey
        }

        return SupabaseConfig(
            url: url,
            publishableKey: rawKey,
            bootstrapFunctionName: bootstrapFunctionName.isEmpty ? "community-bootstrap-user" : bootstrapFunctionName,
            feedFunctionName: feedFunctionName.isEmpty ? "community-feed" : feedFunctionName,
            weatherFunctionName: weatherFunctionName.isEmpty ? "campus-weather" : weatherFunctionName,
            campusAIFunctionName: campusAIFunctionName.isEmpty ? "campus-ai-assistant" : campusAIFunctionName,
            edgeRegion: edgeRegion.isEmpty ? "ap-northeast-1" : edgeRegion,
            communityAPIBaseURL: rawCommunityAPIBaseURL.isEmpty ? nil : URL(string: rawCommunityAPIBaseURL)
        )
    }

    private static func sanitizedBuildSetting(_ value: Any?) -> String {
        let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholders = [
            "https://your-project-ref.supabase.co",
            "sb_publishable_xxx"
        ]

        if raw.isEmpty || raw.hasPrefix("$(") || placeholders.contains(raw) {
            return ""
        }

        return raw
    }
}
