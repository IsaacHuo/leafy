import Foundation
import Supabase

nonisolated final class LeafySupabase {
    static let shared = LeafySupabase()
    static let authCallbackURL = URL(string: "leafy://auth/callback")!

    let configResult: Result<SupabaseConfig, Error>
    let client: SupabaseClient?

    private static let requestTimeout: TimeInterval = 15

    private init(bundle: Bundle = .main) {
        do {
            let config = try SupabaseConfig.load(from: bundle)
            self.configResult = .success(config)
            self.client = SupabaseClient(
                supabaseURL: config.url,
                supabaseKey: config.publishableKey,
                options: SupabaseClientOptions(
                    auth: .init(
                        redirectToURL: Self.authCallbackURL,
                        emitLocalSessionAsInitialSession: true
                    ),
                    global: .init(session: Self.makeURLSession()),
                    functions: .init(region: config.edgeRegion)
                )
            )
        } catch {
            self.configResult = .failure(error)
            self.client = nil
        }
    }

    private static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: configuration)
    }

    func requireClient() throws -> SupabaseClient {
        if let client {
            return client
        }
        switch configResult {
        case .success:
            throw SupabaseConfigError.missingURL
        case .failure(let error):
            throw error
        }
    }

    func requireConfig() throws -> SupabaseConfig {
        try configResult.get()
    }
}
