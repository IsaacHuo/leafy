import Foundation
import Combine
import StoreKit
import Supabase

nonisolated enum CampusAIManagedEntitlementError: LocalizedError {
    case appTransactionUnavailable
    case productUnavailable
    case purchasePending
    case purchaseCancelled

    var errorDescription: String? {
        switch self {
        case .appTransactionUnavailable:
            return "无法验证当前 App 安装记录，请稍后再试。"
        case .productUnavailable:
            return "Leafy AI 订阅暂时不可用。"
        case .purchasePending:
            return "购买正在等待确认。"
        case .purchaseCancelled:
            return "购买已取消。"
        }
    }
}

nonisolated struct CampusAIAppTransactionPayload: Hashable {
    let appTransactionID: String
    let jwsRepresentation: String
}

nonisolated enum CampusAIManagedEntitlementClient {
    static let monthlyProductID = "com.isaachuo.leafy.ai.monthly"
    private static let entitlementFunctionName = "campus-ai-entitlement"

    static func appTransactionPayload() async throws -> CampusAIAppTransactionPayload {
        let verification = try await AppTransaction.shared
        let appTransaction = try verification.payloadValue
        guard let appTransactionID = nonEmptyTrimmed(appTransaction.appTransactionID) else {
            throw CampusAIManagedEntitlementError.appTransactionUnavailable
        }
        return CampusAIAppTransactionPayload(
            appTransactionID: appTransactionID,
            jwsRepresentation: verification.jwsRepresentation
        )
    }

    static func currentSubscriptionJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? result.payloadValue,
                  transaction.productID == monthlyProductID,
                  transaction.revocationDate == nil
            else {
                continue
            }
            if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                continue
            }
            return result.jwsRepresentation
        }
        return nil
    }

    static func sync(transactionJWS: String? = nil) async throws -> CampusAIQuotaSnapshot {
        try await CommunityService.shared.ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        let appTransaction = try await appTransactionPayload()
        let effectiveTransactionJWS: String?
        if let transactionJWS {
            effectiveTransactionJWS = transactionJWS
        } else {
            effectiveTransactionJWS = await currentSubscriptionJWS()
        }

        var url = config.url
        url.appendPathComponent("functions")
        url.appendPathComponent("v1")
        url.appendPathComponent(entitlementFunctionName)
        url.appendPathComponent("sync")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SyncRequest(
                appTransactionID: appTransaction.appTransactionID,
                appTransactionJWS: appTransaction.jwsRepresentation,
                transactionJWS: effectiveTransactionJWS
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CampusAIServiceError.invalidProviderResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let payload = try? JSONDecoder().decode(SyncErrorResponse.self, from: data),
               let error = nonEmptyTrimmed(payload.error) {
                throw CampusAIServiceError.providerRejected(error)
            }
            throw CampusAIServiceError.managedServiceUnavailable
        }
        return try JSONDecoder().decode(SyncResponse.self, from: data).quota
    }

    private struct SyncRequest: Encodable {
        let appTransactionID: String
        let appTransactionJWS: String
        let transactionJWS: String?

        enum CodingKeys: String, CodingKey {
            case appTransactionID = "app_transaction_id"
            case appTransactionJWS = "app_transaction_jws"
            case transactionJWS = "transaction_jws"
        }
    }

    private struct SyncResponse: Decodable {
        let quota: CampusAIQuotaSnapshot
    }

    private struct SyncErrorResponse: Decodable {
        let error: String
    }
}

@MainActor
final class CampusAISubscriptionStore: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var quota: CampusAIQuotaSnapshot?
    @Published private(set) var isPurchased = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    var displayPrice: String? {
        product?.displayPrice
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [CampusAIManagedEntitlementClient.monthlyProductID])
            product = products.first
            let transactionJWS = await CampusAIManagedEntitlementClient.currentSubscriptionJWS()
            isPurchased = transactionJWS != nil
            quota = try await CampusAIManagedEntitlementClient.sync(transactionJWS: transactionJWS)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase() async {
        guard let product else {
            errorMessage = CampusAIManagedEntitlementError.productUnavailable.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                quota = try await CampusAIManagedEntitlementClient.sync(transactionJWS: verification.jwsRepresentation)
                isPurchased = true
                await transaction.finish()
                errorMessage = nil
            case .pending:
                errorMessage = CampusAIManagedEntitlementError.purchasePending.localizedDescription
            case .userCancelled:
                errorMessage = CampusAIManagedEntitlementError.purchaseCancelled.localizedDescription
            @unknown default:
                errorMessage = CampusAIManagedEntitlementError.productUnavailable.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            let transactionJWS = await CampusAIManagedEntitlementClient.currentSubscriptionJWS()
            isPurchased = transactionJWS != nil
            quota = try await CampusAIManagedEntitlementClient.sync(transactionJWS: transactionJWS)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

nonisolated private func nonEmptyTrimmed(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}
