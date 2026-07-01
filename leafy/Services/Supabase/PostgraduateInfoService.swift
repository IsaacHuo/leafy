import Foundation
import Supabase

actor PostgraduateInfoService {
    static let shared = PostgraduateInfoService()

    private init() {}

    func fetchPublishedSources(limit: Int = 80) async throws -> [PostgraduateSource] {
        try await CommunityService.shared.ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        let cappedLimit = max(1, min(limit, 120))

        return try await client
            .from("postgraduate_sources")
            .select()
            .eq("status", value: "published")
            .order("verified_at", ascending: false)
            .order("published_at", ascending: false)
            .limit(cappedLimit)
            .execute()
            .value
    }
}
