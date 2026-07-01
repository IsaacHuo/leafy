import CoreLocation
import Foundation
import WeatherKit

nonisolated struct TimetableHourlyWeather: Codable, Equatable, Sendable {
    let date: Date
    let temperature: Double
    let condition: String
    let symbolName: String
    let precipitationChance: Double
    let uvIndex: Int
    let isDaylight: Bool
}

nonisolated struct TimetableWeatherAttribution: Codable, Equatable, Sendable {
    let serviceName: String
    let legalPageURL: URL

    static let appleWeather = TimetableWeatherAttribution(
        serviceName: "Weather",
        legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
    )
}

nonisolated struct TimetableWeatherSnapshot: Codable, Equatable, Sendable {
    let temperature: Double
    let condition: String
    let symbolName: String
    let observedAt: Date
    let hourlyForecast: [TimetableHourlyWeather]
    let attribution: TimetableWeatherAttribution

    var displayText: String {
        "\(Int(temperature.rounded()))° \(condition)"
    }

    var timetableCapsuleText: String {
        "\(Int(temperature.rounded()))℃ \(timetableCapsuleCondition)"
    }

    private var timetableCapsuleCondition: String {
        switch condition.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "晴", "晴天":
            return "晴天"
        case "阴", "阴天":
            return "阴天"
        case "雨", "雨天":
            return "雨天"
        case "毛毛雨", "小雨":
            return "小雨"
        case "雪", "雪天":
            return "雪天"
        case "雾", "有雾", "雾天":
            return "雾天"
        case "多云":
            return "多云"
        case "雷雨":
            return "雷雨"
        default:
            return "天气"
        }
    }
}

nonisolated enum TimetableWeatherAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

nonisolated enum TimetableWeatherServiceError: LocalizedError, Equatable, Sendable {
    case permissionRequired
    case permissionDenied
    case locationUnavailable
    case noLocation
    case weatherUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "需要允许定位后，才能查看当前位置天气。"
        case .permissionDenied:
            return "定位权限未开启。"
        case .locationUnavailable:
            return "当前设备定位服务不可用。"
        case .noLocation:
            return "暂时无法获取当前位置。"
        case .weatherUnavailable:
            return "天气暂不可用，请稍后重试。"
        }
    }
}

protocol TimetableWeatherServicing: Sendable {
    @MainActor func authorizationState() -> TimetableWeatherAuthorizationState
    @MainActor func fetchCurrentWeather(requestsPermissionIfNeeded: Bool) async throws -> TimetableWeatherSnapshot
    @MainActor func cachedWeather(maxAge: TimeInterval) -> TimetableWeatherSnapshot?
}

protocol TimetableLocationProviding: Sendable {
    @MainActor func authorizationState() -> TimetableWeatherAuthorizationState
    @MainActor func currentLocation(requestsPermissionIfNeeded: Bool) async throws -> CLLocation
}

protocol TimetableWeatherCaching: Sendable {
    func save(_ snapshot: TimetableWeatherSnapshot)
    func currentWeather(maxAge: TimeInterval) -> TimetableWeatherSnapshot?
}

nonisolated struct WeatherKitTimetableWeatherService: TimetableWeatherServicing {
    typealias WeatherFetcher = @Sendable (CLLocation) async throws -> TimetableWeatherSnapshot

    private let makeLocationProvider: @MainActor @Sendable () -> any TimetableLocationProviding
    private let weatherFetcher: WeatherFetcher
    private let cache: any TimetableWeatherCaching

    init(
        locationProvider: (any TimetableLocationProviding)? = nil,
        weatherFetcher: @escaping WeatherFetcher = WeatherKitTimetableWeatherService.fetchWeatherKitSnapshot,
        cache: any TimetableWeatherCaching = UserDefaultsTimetableWeatherCache()
    ) {
        self.makeLocationProvider = {
            locationProvider ?? CoreLocationTimetableLocationProvider()
        }
        self.weatherFetcher = weatherFetcher
        self.cache = cache
    }

    func authorizationState() -> TimetableWeatherAuthorizationState {
        makeLocationProvider().authorizationState()
    }

    func cachedWeather(maxAge: TimeInterval = Self.cacheMaxAge) -> TimetableWeatherSnapshot? {
        cache.currentWeather(maxAge: maxAge)
    }

    func fetchCurrentWeather(requestsPermissionIfNeeded: Bool) async throws -> TimetableWeatherSnapshot {
        do {
            let locationProvider = makeLocationProvider()
            let location = try await locationProvider.currentLocation(requestsPermissionIfNeeded: requestsPermissionIfNeeded)
            let snapshot = try await weatherFetcher(location)
            cache.save(snapshot)
            return snapshot
        } catch {
            if let cached = cache.currentWeather(maxAge: Self.cacheMaxAge) {
                return cached
            }

            if let weatherError = error as? TimetableWeatherServiceError {
                throw weatherError
            }
            throw TimetableWeatherServiceError.weatherUnavailable
        }
    }

    private static let cacheMaxAge: TimeInterval = 30 * 60

    private static func fetchWeatherKitSnapshot(location: CLLocation) async throws -> TimetableWeatherSnapshot {
        let service = WeatherService.shared
        let (current, hourly) = try await service.weather(for: location, including: .current, .hourly)
        let attribution = await fetchAttribution(from: service)
        return makeSnapshot(current: current, hourly: hourly, attribution: attribution)
    }

    private static func fetchAttribution(from service: WeatherService) async -> TimetableWeatherAttribution {
        do {
            let attribution = try await service.attribution
            return TimetableWeatherAttribution(
                serviceName: attribution.serviceName,
                legalPageURL: attribution.legalPageURL
            )
        } catch {
            return .appleWeather
        }
    }

    private static func makeSnapshot(
        current: CurrentWeather,
        hourly: Forecast<HourWeather>,
        attribution: TimetableWeatherAttribution
    ) -> TimetableWeatherSnapshot {
        TimetableWeatherSnapshot(
            temperature: current.temperature.converted(to: .celsius).value,
            condition: localizedCondition(rawValue: current.condition.rawValue, symbolName: current.symbolName),
            symbolName: current.symbolName,
            observedAt: current.date,
            hourlyForecast: hourly.forecast.prefix(24).map { hour in
                TimetableHourlyWeather(
                    date: hour.date,
                    temperature: hour.temperature.converted(to: .celsius).value,
                    condition: localizedCondition(rawValue: hour.condition.rawValue, symbolName: hour.symbolName),
                    symbolName: hour.symbolName,
                    precipitationChance: hour.precipitationChance,
                    uvIndex: hour.uvIndex.value,
                    isDaylight: hour.isDaylight
                )
            },
            attribution: attribution
        )
    }

    private static func localizedCondition(rawValue: String, symbolName: String) -> String {
        let key = "\(rawValue) \(symbolName)".lowercased()

        if key.contains("thunder") || key.contains("storm") {
            return "雷雨"
        }
        if key.contains("snow") || key.contains("sleet") || key.contains("flurr") || key.contains("wintry") {
            return "雪"
        }
        if key.contains("rain") || key.contains("showers") || key.contains("drizzle") {
            return key.contains("drizzle") ? "毛毛雨" : "雨"
        }
        if key.contains("fog") || key.contains("haze") || key.contains("smoky") || key.contains("dust") {
            return "雾"
        }
        if key.contains("cloud") {
            return "多云"
        }
        if key.contains("clear") || key.contains("sun") || key.contains("hot") {
            return "晴"
        }

        return "天气"
    }
}

nonisolated struct UserDefaultsTimetableWeatherCache: TimetableWeatherCaching {
    private nonisolated(unsafe) let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "timetableWeather.cache.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func save(_ snapshot: TimetableWeatherSnapshot) {
        let cached = CachedTimetableWeather(snapshot: snapshot, savedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        userDefaults.set(data, forKey: key)
    }

    func currentWeather(maxAge: TimeInterval) -> TimetableWeatherSnapshot? {
        guard let data = userDefaults.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedTimetableWeather.self, from: data),
              Date().timeIntervalSince(cached.savedAt) <= maxAge else {
            return nil
        }
        return cached.snapshot
    }
}

private nonisolated struct CachedTimetableWeather: Codable {
    let snapshot: TimetableWeatherSnapshot
    let savedAt: Date
}

@MainActor
final class CoreLocationTimetableLocationProvider: NSObject, TimetableLocationProviding, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func authorizationState() -> TimetableWeatherAuthorizationState {
        return Self.authorizationState(from: manager.authorizationStatus)
    }

    func currentLocation(requestsPermissionIfNeeded: Bool) async throws -> CLLocation {
        if Self.isAuthorized(manager.authorizationStatus) {
            return try await requestOneShotLocation()
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            guard requestsPermissionIfNeeded else {
                throw TimetableWeatherServiceError.permissionRequired
            }
            let status = await requestAuthorization()
            guard Self.isAuthorized(status) else {
                throw TimetableWeatherServiceError.permissionDenied
            }
        case .denied, .restricted:
            throw TimetableWeatherServiceError.permissionDenied
        case .authorizedAlways:
            break
#if !os(macOS)
        case .authorizedWhenInUse:
            break
#endif
        @unknown default:
            throw TimetableWeatherServiceError.locationUnavailable
        }

        return try await requestOneShotLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              let continuation = locationContinuation else {
            return
        }
        locationContinuation = nil
        continuation.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        if let locationError = error as? CLError, locationError.code == .denied {
            continuation.resume(throwing: TimetableWeatherServiceError.locationUnavailable)
        } else {
            continuation.resume(throwing: error)
        }
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
#if os(macOS)
            manager.requestAlwaysAuthorization()
#else
            manager.requestWhenInUseAuthorization()
#endif
        }
    }

    private func requestOneShotLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private static func authorizationState(from status: CLAuthorizationStatus) -> TimetableWeatherAuthorizationState {
        if isAuthorized(status) {
            return .authorized
        }

        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorizedAlways:
            return .authorized
#if !os(macOS)
        case .authorizedWhenInUse:
            return .authorized
#endif
        @unknown default:
            return .unavailable
        }
    }

    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
#if os(macOS)
        status == .authorizedAlways
#else
        status == .authorizedAlways || status == .authorizedWhenInUse
#endif
    }
}
