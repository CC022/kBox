import Foundation

/// Latest mortgage rates, keyed by term in years ("15" / "20" / "30").
public struct MarketRates: Codable, Sendable, Equatable {
    public struct Weekly: Codable, Sendable, Equatable {
        public var asOf: String
        public var rate30: Double
        public var rate15: Double
    }

    public var asOf: String
    public var source: String
    public var conforming: [String: Double]
    public var jumbo: [String: Double]
    /// Entries like "jumbo.15" that are interpolated rather than published.
    public var estimated: [String]
    /// Freddie Mac PMMS weekly average, shown for reference.
    public var weekly: Weekly?
    public var fetchedAt: Date

    /// `type` must already be resolved (conforming or jumbo).
    public func rate(for type: LoanType, term: LoanTerm) -> (rate: Double, estimated: Bool)? {
        let key = type == .jumbo ? "jumbo" : "conforming"
        let table = type == .jumbo ? jumbo : conforming
        guard let rate = table[String(term.years)] else { return nil }
        return (rate, estimated.contains("\(key).\(term.years)"))
    }
}

public enum RateError: LocalizedError, Equatable {
    case http(Int)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code): "服务器返回 HTTP \(code)"
        case .unavailable(let detail): "获取利率失败：\(detail)"
        }
    }
}

/// Fetches rates straight from FRED (no proxy needed in a native app).
/// - Daily Optimal Blue: conforming 30 / 15, jumbo 30.
/// - Weekly Freddie Mac PMMS: 30 / 15 — fallback and reference.
/// There is no public 20-year series, and no jumbo 15-year one; those are estimated.
public struct RateService: Sendable {
    public struct Observation: Sendable, Equatable {
        public var date: String
        public var value: Double
    }

    static let endpoint = "https://fred.stlouisfed.org/graph/fredgraph.csv?id="
    static let daily = ["OBMMIC30YF", "OBMMIC15YF", "OBMMIJUMBO30YF"]
    static let weekly = ["MORTGAGE30US", "MORTGAGE15US"]

    public init() {}

    public func fetch() async throws -> MarketRates {
        async let dailyResult = latestResult(Self.daily)
        async let weeklyResult = latestResult(Self.weekly)
        return try Self.build(daily: await dailyResult, weekly: await weeklyResult)
    }

    private func latestResult(_ series: [String]) async -> Result<[String: Observation], Error> {
        do {
            return .success(try await latest(series))
        } catch {
            return .failure(error)
        }
    }

    private func latest(_ series: [String]) async throws -> [String: Observation] {
        guard let url = URL(string: Self.endpoint + series.joined(separator: ",")) else { throw URLError(.badURL) }
        // Keep the default User-Agent: FRED's bot filter rejects spoofed browser agents.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw RateError.http(http.statusCode) }
        return Self.parseLatest(String(decoding: data, as: UTF8.self))
    }

    /// Most recent non-empty value of every column in a FRED CSV.
    static func parseLatest(_ csv: String) -> [String: Observation] {
        let lines = csv.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
        guard let headerLine = lines.first else { return [:] }
        let ids = headerLine.split(separator: ",", omittingEmptySubsequences: false)
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var latest: [String: Observation] = [:]
        for line in lines.dropFirst().reversed() {
            let cells = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            for (offset, id) in ids.enumerated() where latest[id] == nil {
                let index = offset + 1
                guard index < cells.count, let value = Double(cells[index]) else { continue }
                latest[id] = Observation(date: cells[0], value: value)
            }
            if latest.count == ids.count { break }
        }
        return latest
    }

    static func build(
        daily: Result<[String: Observation], Error>,
        weekly: Result<[String: Observation], Error>,
        now: Date = .now
    ) throws -> MarketRates {
        var problems: [String] = []
        let d = (try? daily.get()) ?? [:]
        let w = (try? weekly.get()) ?? [:]
        if case .failure(let error) = daily { problems.append("Optimal Blue \(describe(error))") }
        if case .failure(let error) = weekly { problems.append("Freddie Mac \(describe(error))") }

        var weeklyRates: MarketRates.Weekly?
        if let w30 = w["MORTGAGE30US"], let w15 = w["MORTGAGE15US"] {
            weeklyRates = .init(asOf: w30.date, rate30: w30.value, rate15: w15.value)
        }

        var estimated = ["conforming.20", "jumbo.15", "jumbo.20"]
        let c30: Double, c15: Double, j30: Double, asOf: String, source: String
        if let a = d["OBMMIC30YF"], let b = d["OBMMIC15YF"], let j = d["OBMMIJUMBO30YF"] {
            c30 = a.value
            c15 = b.value
            j30 = j.value
            asOf = max(a.date, b.date, j.date)
            source = "Optimal Blue"
        } else if let wk = weeklyRates {
            c30 = wk.rate30
            c15 = wk.rate15
            asOf = wk.asOf
            source = "Freddie Mac PMMS"
            if let j = d["OBMMIJUMBO30YF"] {
                j30 = j.value
            } else {
                j30 = c30
                estimated.append("jumbo.30")
            }
        } else {
            throw RateError.unavailable(problems.isEmpty ? "没有可用的利率数据" : problems.joined(separator: "；"))
        }

        // Jumbo 15-year: apply the observed 30-year jumbo spread to the conforming 15-year rate.
        let j15 = c15 + (j30 - c30)
        return MarketRates(
            asOf: asOf,
            source: source,
            conforming: curve(c15, c30),
            jumbo: curve(j15, j30),
            estimated: estimated,
            weekly: weeklyRates,
            fetchedAt: now
        )
    }

    /// 20-year: linear interpolation by term between 15 and 30.
    private static func curve(_ r15: Double, _ r30: Double) -> [String: Double] {
        let round3 = { (v: Double) in (v * 1000).rounded() / 1000 }
        return ["15": round3(r15), "20": round3(r15 + (r30 - r15) / 3), "30": round3(r30)]
    }

    private static func describe(_ error: Error) -> String {
        switch (error as? URLError)?.code {
        case .timedOut?: "请求超时"
        case .notConnectedToInternet?, .networkConnectionLost?: "网络不可用"
        default: error.localizedDescription
        }
    }
}
