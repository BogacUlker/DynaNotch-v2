//
//  WeatherView.swift
//  boringNotch
//
//  Weather tab view for the expanded notch.
//

import Defaults
import SwiftUI

struct WeatherView: View {
    @ObservedObject var weather = WeatherManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 20) {
            // Left: Current weather
            currentSection

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)

            // Right: Hourly forecast
            forecastSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        ))
    }

    // MARK: - Current Weather (Left)

    private var currentSection: some View {
        VStack(spacing: 4) {
            if weather.isLoading && weather.temperature == nil {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading...")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            } else if weather.temperature != nil {
                Image(systemName: weather.sfSymbol)
                    .font(.system(size: 36))
                    .symbolRenderingMode(.multicolor)

                Text(weather.temperatureDisplay)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text(weather.weatherDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)

                HStack(spacing: 8) {
                    if !weather.cityName.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 9))
                            Text(weather.cityName)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.gray.opacity(0.8))
                    }

                    if Defaults[.weatherShowHumidity], let humidity = weather.humidity {
                        HStack(spacing: 3) {
                            Image(systemName: "humidity.fill")
                                .font(.system(size: 9))
                            Text("\(humidity)%")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.cyan.opacity(0.7))
                    }
                }
            } else {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
                Text("No data")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hourly Forecast (Right)

    private var forecastSection: some View {
        VStack(spacing: 8) {
            Text("FORECAST")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(1)

            if weather.hourlyForecast.isEmpty {
                Spacer()
                Text("--")
                    .font(.system(size: 13))
                    .foregroundColor(.gray.opacity(0.5))
                Spacer()
            } else {
                HStack(spacing: 12) {
                    ForEach(weather.hourlyForecast) { hour in
                        VStack(spacing: 5) {
                            Text(hour.hour)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)

                            Image(systemName: WeatherManager.wmoSFSymbol(hour.weatherCode))
                                .font(.system(size: 18))
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 22)

                            Text(formatTemp(hour.temperature))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatTemp(_ temp: Double) -> String {
        let unit = Defaults[.temperatureUnit]
        if unit == "fahrenheit" {
            let f = temp * 9.0 / 5.0 + 32.0
            return String(format: "%.0f°", f)
        }
        return String(format: "%.0f°", temp)
    }
}
