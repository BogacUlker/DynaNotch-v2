//
//  EuroLeagueProvider.swift
//  boringNotch
//
//  Fetches EuroLeague basketball data from the v1 XML API.
//

import Foundation
import os

/// Fetches EuroLeague basketball data from the v1 XML API.
/// Used as a sub-provider within BasketballProvider.
final class EuroLeagueProvider {
    private let logger = Logger(subsystem: "com.dynanotch.app", category: "EuroLeagueProvider")
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private(set) var games: [BasketballGame] = []
    private(set) var standings: [BasketballStanding] = []

    // MARK: - Season Code

    static func currentSeasonCode() -> String {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let seasonYear = month >= 9 ? year : year - 1
        return "E\(seasonYear)"
    }

    // MARK: - Refresh

    func refresh() async {
        let season = Self.currentSeasonCode()
        async let standingsTask: () = refreshStandings(season: season)
        async let scheduleTask: () = refreshSchedule(season: season)
        _ = await (standingsTask, scheduleTask)
    }

    // MARK: - Standings

    private func refreshStandings(season: String) async {
        do {
            guard let url = URL(string: "https://api-live.euroleague.net/v1/standings?seasonCode=\(season)") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)
            let parser = EuroLeagueXMLParser(mode: .standings)
            parser.parse(data: data)
            standings = parser.parsedStandings
            logger.info("EuroLeague standings: parsed \(self.standings.count) teams")
        } catch {
            logger.error("EuroLeague standings error: \(error.localizedDescription)")
        }
    }

    // MARK: - Schedule + Results

    private func refreshSchedule(season: String) async {
        do {
            guard let scheduleURL = URL(string: "https://api-live.euroleague.net/v1/schedules?seasonCode=\(season)"),
                  let resultsURL = URL(string: "https://api-live.euroleague.net/v1/results?seasonCode=\(season)")
            else { return }

            async let scheduleData = fetchData(from: scheduleURL)
            async let resultsData = fetchData(from: resultsURL)

            let sData = try await scheduleData
            let rData = try await resultsData

            let resultsParser = EuroLeagueXMLParser(mode: .results)
            resultsParser.parse(data: rData)
            let scoreLookup = resultsParser.parsedScores

            let scheduleParser = EuroLeagueXMLParser(mode: .schedule)
            scheduleParser.parse(data: sData)

            games = scheduleParser.parsedGames.map { game in
                var g = game
                let key = "\(g.homeAbbrev)-\(g.awayAbbrev)"
                if g.status == .finished, let scores = scoreLookup[key] {
                    g.homeScore = scores.home
                    g.awayScore = scores.away
                }
                if g.status == .scheduled {
                    let now = Date()
                    let threeHoursAfter = g.startDate.addingTimeInterval(3 * 3600)
                    if g.startDate <= now && now <= threeHoursAfter {
                        g.status = .live
                        g.period = "LIVE"
                    }
                }
                return g
            }.sorted { $0.startDate < $1.startDate }

            logger.info("EuroLeague schedule: \(self.games.count) games (\(self.games.filter(\.isLive).count) possibly live)")
        } catch {
            logger.error("EuroLeague schedule error: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Queries

    var hasStandingsData: Bool { !standings.isEmpty }

    func allTeams() -> [(abbrev: String, displayName: String)] {
        var seen = Set<String>()
        var result: [(abbrev: String, displayName: String)] = []
        for team in standings {
            guard !team.teamAbbrev.isEmpty, !seen.contains(team.teamAbbrev) else { continue }
            seen.insert(team.teamAbbrev)
            result.append((abbrev: team.teamAbbrev, displayName: "\(team.teamName) (\(team.teamAbbrev))"))
        }
        return result.sorted { $0.displayName < $1.displayName }
    }

    func liveEvents() -> [SportEvent] {
        games.filter(\.isLive).map { game in
            SportEvent(
                id: "el-\(game.id)",
                type: .basketball,
                isLive: true,
                collapsedText: game.collapsedText,
                startDate: game.startDate
            )
        }
    }
}

// MARK: - XML Parser

private final class EuroLeagueXMLParser: NSObject, XMLParserDelegate {
    enum Mode {
        case standings
        case schedule
        case results
    }

    let mode: Mode

    var parsedStandings: [BasketballStanding] = []
    var parsedGames: [BasketballGame] = []
    var parsedScores: [String: (home: Int, away: Int)] = [:]

    private var currentElement = ""
    private var currentValues: [String: String] = [:]
    private var isInsideRecord = false

    private var recordElementName: String {
        switch mode {
        case .standings: return "team"
        case .schedule: return "item"
        case .results: return "game"
        }
    }

    init(mode: Mode) {
        self.mode = mode
    }

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let lower = elementName.lowercased()
        if lower == recordElementName {
            isInsideRecord = true
            currentValues = [:]
        }
        if isInsideRecord {
            currentElement = lower
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideRecord else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentValues[currentElement, default: ""] += trimmed
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let lower = elementName.lowercased()
        guard lower == recordElementName else { return }
        isInsideRecord = false

        switch mode {
        case .standings: buildStanding()
        case .schedule: buildGame()
        case .results: buildScore()
        }
        currentValues = [:]
    }

    // MARK: - Record Builders

    private func buildStanding() {
        let name = currentValues["name"] ?? currentValues["clubname"] ?? ""
        let code = currentValues["code"] ?? currentValues["clubcode"] ?? ""
        let ranking = Int(currentValues["ranking"] ?? currentValues["position"] ?? "0") ?? 0
        let wins = Int(currentValues["wins"] ?? "0") ?? 0
        let losses = Int(currentValues["losses"] ?? "0") ?? 0
        let totalGames = Int(currentValues["totalgames"] ?? currentValues["gamesplayed"] ?? "0") ?? 0
        let winPct = totalGames > 0 ? Double(wins) / Double(totalGames) : 0

        guard !code.isEmpty else { return }

        parsedStandings.append(BasketballStanding(
            id: "el-\(code)",
            position: ranking,
            teamName: name,
            teamAbbrev: code,
            wins: wins,
            losses: losses,
            winPct: winPct,
            conference: "EuroLeague",
            league: "EuroLeague"
        ))
    }

    private func buildGame() {
        let gameCode = currentValues["gamecode"] ?? UUID().uuidString
        let homeTeam = currentValues["hometeam"] ?? ""
        let homeCode = currentValues["homecode"] ?? ""
        let awayTeam = currentValues["awayteam"] ?? ""
        let awayCode = currentValues["awaycode"] ?? ""
        let played = (currentValues["played"] ?? "").lowercased() == "true"

        guard !homeCode.isEmpty, !awayCode.isEmpty else { return }

        let startDate = parseEuroLeagueDate(
            date: currentValues["date"] ?? "",
            time: currentValues["startime"] ?? currentValues["starttime"] ?? ""
        )

        let status: GameStatus = played ? .finished : .scheduled

        parsedGames.append(BasketballGame(
            id: "el-\(gameCode)",
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeAbbrev: homeCode,
            awayAbbrev: awayCode,
            homeScore: nil,
            awayScore: nil,
            status: status,
            period: nil,
            startDate: startDate,
            league: "EuroLeague"
        ))
    }

    private func buildScore() {
        let homeCode = currentValues["homecode"] ?? ""
        let awayCode = currentValues["awaycode"] ?? ""
        guard !homeCode.isEmpty, !awayCode.isEmpty else { return }

        let homeScore = Int(currentValues["homescore"] ?? "") ?? 0
        let awayScore = Int(currentValues["awayscore"] ?? "") ?? 0
        let key = "\(homeCode)-\(awayCode)"
        parsedScores[key] = (home: homeScore, away: awayScore)
    }

    // MARK: - Date Parsing

    private func parseEuroLeagueDate(date: String, time: String) -> Date {
        let combined = date.isEmpty ? "" : "\(date) \(time)"
        guard !combined.trimmingCharacters(in: .whitespaces).isEmpty else { return Date.distantFuture }

        let formats = [
            "MMM dd, yyyy HH:mm",
            "MMMM dd, yyyy HH:mm",
            "MMM dd, yyyy",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Madrid")

        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: combined) {
                return parsed
            }
        }

        if !date.isEmpty {
            for format in ["MMM dd, yyyy", "MMMM dd, yyyy", "yyyy-MM-dd"] {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: date) {
                    return parsed
                }
            }
        }

        return Date.distantFuture
    }
}
