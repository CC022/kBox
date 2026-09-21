import Foundation
import Testing
@testable import KBoxKit

struct RateServiceTests {
    static let dailyCSV = """
    observation_date,OBMMIC30YF,OBMMIC15YF,OBMMIJUMBO30YF
    2026-09-15,6.985,6.391,7.014
    2026-09-16,7.047,6.436,7.038
    2026-09-17,,,
    """

    static let weeklyCSV = """
    observation_date,MORTGAGE30US,MORTGAGE15US\r
    2026-09-10,6.76,6.09\r
    2026-09-17,6.95,6.26\r
    """

    @Test func parsesMostRecentNonEmptyValues() {
        let latest = RateService.parseLatest(Self.dailyCSV)
        #expect(latest["OBMMIC30YF"] == .init(date: "2026-09-16", value: 7.047))
        #expect(latest["OBMMIJUMBO30YF"]?.value == 7.038)
        #expect(RateService.parseLatest(Self.weeklyCSV)["MORTGAGE15US"] == .init(date: "2026-09-17", value: 6.26))
    }

    @Test func buildsRatesFromDailySeries() throws {
        let rates = try RateService.build(
            daily: .success(RateService.parseLatest(Self.dailyCSV)),
            weekly: .success(RateService.parseLatest(Self.weeklyCSV))
        )
        #expect(rates.source == "Optimal Blue")
        #expect(rates.asOf == "2026-09-16")
        #expect(rates.conforming == ["15": 6.436, "20": 6.64, "30": 7.047])
        #expect(rates.jumbo == ["15": 6.427, "20": 6.631, "30": 7.038])
        #expect(rates.rate(for: .jumbo, term: .thirty)! == (7.038, false))
        #expect(rates.rate(for: .jumbo, term: .fifteen)! == (6.427, true))
        #expect(rates.weekly == .init(asOf: "2026-09-17", rate30: 6.95, rate15: 6.26))
    }

    @Test func fallsBackToWeeklyWhenDailyFails() throws {
        let rates = try RateService.build(
            daily: .failure(URLError(.timedOut)),
            weekly: .success(RateService.parseLatest(Self.weeklyCSV))
        )
        #expect(rates.source == "Freddie Mac PMMS")
        #expect(rates.conforming["30"] == 6.95)
        #expect(rates.estimated.contains("jumbo.30"))
    }

    @Test func failsWhenNoSourceWorks() {
        #expect(throws: RateError.self) {
            try RateService.build(daily: .failure(URLError(.timedOut)), weekly: .failure(URLError(.notConnectedToInternet)))
        }
    }
}
