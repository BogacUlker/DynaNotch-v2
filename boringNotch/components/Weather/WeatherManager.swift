//
//  WeatherManager.swift
//  boringNotch
//
//  Weather data manager using Open-Meteo API and CoreLocation.
//

import Combine
import CoreLocation
import Defaults
import Foundation
import os

/// A single hour's forecast data.
struct HourForecast: Identifiable {
    let id = UUID()
    let hour: String
    let temperature: Double
    let weatherCode: Int
}

@MainActor
class WeatherManager: NSObject, ObservableObject {

    static let shared = WeatherManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringNotch", category: "Weather")

    // MARK: - Published State

    @Published var temperature: Double?
    @Published var humidity: Int?
    @Published var weatherCode: Int = -1
    @Published var weatherDescription: String = ""
    @Published var cityName: String = ""
    @Published var isLoading: Bool = false
    @Published var hourlyForecast: [HourForecast] = []

    // MARK: - Computed

    var temperatureDisplay: String {
        guard let temp = temperature else { return "--" }
        let unit = Defaults[.temperatureUnit]
        if unit == "fahrenheit" {
            let f = temp * 9.0 / 5.0 + 32.0
            return String(format: "%.0f°F", f)
        }
        return String(format: "%.0f°C", temp)
    }

    var sfSymbol: String {
        Self.wmoSFSymbol(weatherCode)
    }

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var fetchTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var lastLocation: CLLocation?

    // MARK: - Init

    private override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        Defaults.publisher(.enableWeather)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        self?.startMonitoring()
                    } else {
                        self?.stopMonitoring()
                    }
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.weatherManualCity)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard Defaults[.enableWeather] else { return }
                    let city = change.newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if city.isEmpty {
                        self?.locationManager.startUpdatingLocation()
                    } else {
                        self?.geocodeCity(city)
                    }
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.temperatureUnit)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.weatherUpdateInterval)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard Defaults[.enableWeather] else { return }
                    self?.stopMonitoring()
                    self?.startMonitoring()
                }
            }
            .store(in: &cancellables)

        if Defaults[.enableWeather] {
            startMonitoring()
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        logger.info("[WEATHER] startMonitoring")

        let manualCity = Defaults[.weatherManualCity].trimmingCharacters(in: .whitespacesAndNewlines)
        if manualCity.isEmpty {
            locationManager.startUpdatingLocation()
        } else {
            geocodeCity(manualCity)
        }

        fetchTimer?.cancel()
        let intervalMinutes = Defaults[.weatherUpdateInterval]
        fetchTimer = Timer.publish(every: TimeInterval(intervalMinutes * 60), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshWeather()
                }
            }
    }

    private func stopMonitoring() {
        logger.info("[WEATHER] stopMonitoring")
        fetchTimer?.cancel()
        fetchTimer = nil
        locationManager.stopUpdatingLocation()
    }

    private func refreshWeather() {
        let manualCity = Defaults[.weatherManualCity].trimmingCharacters(in: .whitespacesAndNewlines)
        if manualCity.isEmpty {
            if let loc = lastLocation {
                fetchWeather(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            } else {
                locationManager.startUpdatingLocation()
            }
        } else {
            geocodeCity(manualCity)
        }
    }

    // MARK: - Geocoding

    private func geocodeCity(_ city: String) {
        geocoder.geocodeAddressString(city) { [weak self] placemarks, error in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("[WEATHER] geocode error: \(error.localizedDescription)")
                return
            }
            guard let location = placemarks?.first?.location else { return }
            Task { @MainActor in
                self.cityName = city
                self.lastLocation = location
                self.fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
        }
    }

    // MARK: - API

    private func fetchWeather(latitude: Double, longitude: Double) {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,relative_humidity_2m,weather_code&hourly=temperature_2m,weather_code&forecast_hours=6&timezone=auto"
        guard let url = URL(string: urlString) else { return }

        isLoading = true
        logger.info("[WEATHER] fetching lat=\(latitude) lon=\(longitude)")

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoading = false
            }

            if let error = error {
                self.logger.error("[WEATHER] fetch error: \(error.localizedDescription)")
                return
            }

            guard let data = data else { return }

            do {
                let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                Task { @MainActor in
                    self.temperature = response.current.temperature_2m
                    self.humidity = Int(response.current.relative_humidity_2m)
                    let code = Int(response.current.weather_code)
                    self.weatherCode = code
                    self.weatherDescription = Self.wmoDescription(code)

                    // Parse hourly forecast
                    if let hourly = response.hourly {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                        let hourFormatter = DateFormatter()
                        hourFormatter.dateFormat = "HH:mm"

                        var forecasts: [HourForecast] = []
                        let count = min(hourly.time.count, hourly.temperature_2m.count, hourly.weather_code.count)
                        // Skip first entry (current hour), show next 5
                        for i in 1..<min(count, 6) {
                            let hourLabel: String
                            if let date = dateFormatter.date(from: hourly.time[i]) {
                                hourLabel = hourFormatter.string(from: date)
                            } else {
                                hourLabel = hourly.time[i]
                            }
                            forecasts.append(HourForecast(
                                hour: hourLabel,
                                temperature: hourly.temperature_2m[i],
                                weatherCode: Int(hourly.weather_code[i])
                            ))
                        }
                        self.hourlyForecast = forecasts
                    }

                    self.logger.info("[WEATHER] updated temp=\(response.current.temperature_2m) code=\(code)")
                }
            } catch {
                self.logger.error("[WEATHER] decode error: \(error.localizedDescription)")
            }
        }.resume()
    }

    // MARK: - WMO → SF Symbol

    static func wmoSFSymbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1: return "sun.min.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57: return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }

    static func wmoDescription(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Hail Storm"
        default: return "Unknown"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            lastLocation = location
            locationManager.stopUpdatingLocation()
            fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                if let city = placemarks?.first?.locality {
                    Task { @MainActor in
                        self?.cityName = city
                    }
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let desc = error.localizedDescription
        Task { @MainActor in
            logger.error("[WEATHER] location error: \(desc)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized {
            Task { @MainActor in
                if Defaults[.enableWeather] && Defaults[.weatherManualCity].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    manager.startUpdatingLocation()
                }
            }
        }
    }
}

// MARK: - API Response

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather
    let hourly: HourlyWeather?

    struct CurrentWeather: Decodable {
        let temperature_2m: Double
        let relative_humidity_2m: Double
        let weather_code: Double
    }

    struct HourlyWeather: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Double]
    }
}
