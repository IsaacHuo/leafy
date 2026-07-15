import Foundation
import Combine
import StoreKit
import Supabase

nonisolated enum CampusAIManagedEntitlementError: LocalizedError {
    case appTransactionUnavailable
    case productUnavailable
    case productNotReturned(productID: String)
    case purchasePending
    case purchaseCancelled

    var errorDescription: String? {
        switch self {
        case .appTransactionUnavailable:
            return "无法验证当前 App 安装记录，请稍后再试。"
        case .productUnavailable:
            return "Leafy AI 订阅暂时不可用。"
        case .productNotReturned(let productID):
            return "StoreKit 没有返回 Leafy AI 周订阅商品（\(productID)）。请确认 App Store Connect 已为 com.isaachuo.leafy 创建同 ID 的自动续订订阅，周期为 1 周，付费协议/税务/银行信息可用，商品价格、地区和本地化信息已填写，并使用 TestFlight 或 Sandbox 环境测试。"
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
    static let weeklyProductID = "com.isaachuo.leafy.ai.weekly.v2"
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
                  transaction.productID == weeklyProductID,
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
    @Published private(set) var pendingMessage: String?
    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let transaction = try? result.payloadValue,
                      transaction.productID == CampusAIManagedEntitlementClient.weeklyProductID
                else { continue }
                do {
                    self?.quota = try await CampusAIManagedEntitlementClient.sync(
                        transactionJWS: result.jwsRepresentation
                    )
                    self?.isPurchased = transaction.revocationDate == nil &&
                        (transaction.expirationDate.map { $0 > Date() } ?? true)
                    self?.errorMessage = nil
                    self?.pendingMessage = nil
                    await transaction.finish()
                } catch {
                    self?.errorMessage = "同步订阅额度失败：\(error.localizedDescription)"
                }
            }
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var productID: String {
        product?.id ?? CampusAIManagedEntitlementClient.weeklyProductID
    }

    var displayPrice: String? {
        product?.displayPrice
    }

    var billingPeriodText: String {
        guard let period = product?.subscription?.subscriptionPeriod else {
            return "周"
        }
        return period.leafyLocalizedText
    }

    var subscriptionQuotaText: String {
        "120 次/\(billingPeriodText)"
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        var messages: [String] = []

        do {
            let products = try await Product.products(for: [CampusAIManagedEntitlementClient.weeklyProductID])
            product = products.first { $0.id == CampusAIManagedEntitlementClient.weeklyProductID }
            if product == nil {
                messages.append(
                    CampusAIManagedEntitlementError
                        .productNotReturned(productID: CampusAIManagedEntitlementClient.weeklyProductID)
                        .localizedDescription
                )
            }
        } catch {
            product = nil
            messages.append("读取 Leafy AI 订阅价格失败：\(error.localizedDescription)")
        }

        let transactionJWS = await CampusAIManagedEntitlementClient.currentSubscriptionJWS()
        isPurchased = transactionJWS != nil

        do {
            quota = try await CampusAIManagedEntitlementClient.sync(transactionJWS: transactionJWS)
        } catch {
            quota = nil
            messages.append("同步 Leafy AI 额度失败：\(error.localizedDescription)")
        }

        errorMessage = messages.isEmpty ? nil : messages.joined(separator: "\n\n")
    }

    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            errorMessage = CampusAIManagedEntitlementError
                .productNotReturned(productID: CampusAIManagedEntitlementClient.weeklyProductID)
                .localizedDescription
            return false
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
                pendingMessage = nil
                return true
            case .pending:
                pendingMessage = CampusAIManagedEntitlementError.purchasePending.localizedDescription
                errorMessage = nil
                return false
            case .userCancelled:
                errorMessage = nil
                pendingMessage = nil
                return false
            @unknown default:
                errorMessage = CampusAIManagedEntitlementError.productUnavailable.localizedDescription
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
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
            pendingMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyQuota(_ quota: CampusAIQuotaSnapshot) {
        self.quota = quota
        isPurchased = quota.planSource == "subscription" && quota.status == "active"
    }
}

nonisolated private func nonEmptyTrimmed(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private extension Product.SubscriptionPeriod {
    var leafyLocalizedText: String {
        let unitText: String
        switch unit {
        case .day:
            unitText = "天"
        case .week:
            unitText = "周"
        case .month:
            unitText = "月"
        case .year:
            unitText = "年"
        @unknown default:
            unitText = "周期"
        }
        return value == 1 ? unitText : "\(value)\(unitText)"
    }
}
