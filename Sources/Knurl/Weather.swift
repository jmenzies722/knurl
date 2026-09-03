import CoreLocation
import Foundation
import KnurlCore
import Observation

// MARK: - Weather
//
// The one thing in Knurl that leaves this Mac, and the only tool that asks for
// a permission it did not previously need. Both facts are stated on the tile
// rather than buried, and neither happens until you turn it on.
//
// Why Open-Meteo and not WeatherKit: WeatherKit needs a paid developer
// entitlement and a signed, provisioned build to work at all, which would
// mean the feature silently fails for anyone running a local build. Open-Meteo
// needs no key, no account and no attribution, so the tile works the moment
// you enable it. The cost is one HTTPS request to a third party carrying a
// coarse latitude and longitude — see `coarse(_:)`, which deliberately throws
// away precision before the request is built.

struct WeatherReading: Equatable, Sendable {
    var temperature: Double
    var apparent: Double
    var code: Int
    var isDay: Bool
    var high: Double?
    var low: Double?
    var place: String
    var at: Date

    var temperatureLabel: String { "\(Int(temperature.rounded()))°" }
    var apparentLabel: String { "Feels \(Int(apparent.rounded()))°" }

    var rangeLabel: String? {
        guard let high, let low else { return nil }
        return "H \(Int(high.rounded()))°  L \(Int(low.rounded()))°"
    }

    /// WMO weather codes, which is what Open-Meteo speaks.
    var summary: String {
        switch code {
        case 0: isDay ? "Clear" : "Clear night"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 65, 66, 67: "Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow showers"
        case 95, 96, 99: "Thunderstorms"
        default: "Weather"
        }
    }

    var symbol: String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: "cloud.rain.fill"
        case 71, 73, 75, 77: "cloud.snow.fill"
        case 80, 81, 82: "cloud.heavyrain.fill"
        case 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

@MainActor
@Observable
final class WeatherDesk: NSObject, CLLocationManagerDelegate {
    private(set) var reading: WeatherReading?
    private(set) var message: String?
    private(set) var isLoading = false

    var enabled = Preferences.weatherEnabled {
        didSet {
            Preferences.weatherEnabled = enabled
            if enabled {
                begin()
            } else {
                reading = nil
                message = nil
                stopTimer()
            }
        }
    }

    private let manager = CLLocationManager()
    private var pump: Task<Void, Never>?
    private var fetching: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func start() {
        guard enabled else { return }
        begin()
    }

    private func begin() {
        switch manager.authorizationStatus {
        case .notDetermined:
            message = "Asking for your location…"
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            message = "Location is off for Knurl. Weather needs it to know where you are."
        default:
            requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard enabled else { return }
            switch status {
            case .denied, .restricted:
                message = "Location is off for Knurl. Weather needs it to know where you are."
            case .notDetermined:
                break
            default:
                message = nil
                requestLocation()
            }
        }
    }

    private func requestLocation() {
        isLoading = reading == nil
        manager.requestLocation()
        startTimer()
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor in
            self.load(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            if self.reading == nil {
                self.message = "Couldn’t work out where this Mac is."
            }
        }
    }

    /// Two decimal places — roughly a kilometre. Weather does not change over
    /// a city block, so there is no reason to hand a third party a coordinate
    /// precise enough to find a building.
    private func coarse(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func load(_ coordinate: CLLocationCoordinate2D) {
        fetching?.cancel()
        fetching = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }

            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: coarse(coordinate.latitude)),
                URLQueryItem(name: "longitude", value: coarse(coordinate.longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,is_day,weather_code"),
                URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                URLQueryItem(name: "temperature_unit", value: Locale.current.usesFahrenheit ? "fahrenheit" : "celsius"),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "forecast_days", value: "1"),
            ]
            guard let url = components.url else { return }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 12
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    self.message = "Weather service didn’t answer."
                    return
                }
                let payload = try JSONDecoder().decode(OpenMeteo.self, from: data)
                guard !Task.isCancelled else { return }
                self.reading = WeatherReading(
                    temperature: payload.current.temperature_2m,
                    apparent: payload.current.apparent_temperature,
                    code: payload.current.weather_code,
                    isDay: payload.current.is_day == 1,
                    high: payload.daily?.temperature_2m_max.first,
                    low: payload.daily?.temperature_2m_min.first,
                    place: payload.timezone?.split(separator: "/").last.map {
                        $0.replacingOccurrences(of: "_", with: " ")
                    } ?? "Here",
                    at: Date()
                )
                self.message = nil
            } catch {
                if self.reading == nil {
                    self.message = "Couldn’t reach the weather service."
                }
            }
        }
    }

    /// Half-hourly. Weather is not live data and a desk accessory has no
    /// business polling a public service harder than that.
    private func startTimer() {
        guard pump == nil else { return }
        pump = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                guard let self, self.enabled else { return }
                self.manager.requestLocation()
            }
        }
    }

    private func stopTimer() {
        pump?.cancel()
        pump = nil
        fetching?.cancel()
        fetching = nil
    }

    private struct OpenMeteo: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var apparent_temperature: Double
            var is_day: Int
            var weather_code: Int
        }

        struct Daily: Decodable {
            var temperature_2m_max: [Double]
            var temperature_2m_min: [Double]
        }

        var current: Current
        var daily: Daily?
        var timezone: String?
    }
}

private extension Locale {
    /// `measurementSystem` is the honest signal here: the US, Liberia and
    /// Myanmar report `.us`, and everyone else gets Celsius.
    var usesFahrenheit: Bool { measurementSystem == .us }
}
