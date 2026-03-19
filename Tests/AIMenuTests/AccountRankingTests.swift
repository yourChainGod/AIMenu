import XCTest
@testable import AIMenu

final class AccountRankingTests: XCTestCase {
    func testPickBestAccountChoosesMostRemainingQuota() {
        let best = makeAccount(id: "a", weekUsed: 15, hourUsed: 30)
        let medium = makeAccount(id: "b", weekUsed: 40, hourUsed: 30)
        let worst = makeAccount(id: "c", weekUsed: 80, hourUsed: 90)

        let picked = AccountRanking.pickBestAccount([worst, medium, best])

        XCTAssertEqual(picked?.id, best.id)
    }

    func testAutoSwitchTargetIsNilWhenCurrentAccountNotExhausted() {
        let current = makeAccount(id: "current", weekUsed: 60, hourUsed: 70, isCurrent: true)
        let better = makeAccount(id: "better", weekUsed: 10, hourUsed: 15)

        let target = AccountRanking.pickAutoSwitchTarget([current, better])

        XCTAssertNil(target)
    }

    func testAutoSwitchTargetChoosesBestAlternativeWhenCurrentIsExhausted() {
        let exhaustedCurrent = makeAccount(id: "current", weekUsed: 100, hourUsed: 95, isCurrent: true)
        let bestAlternative = makeAccount(id: "best", weekUsed: 20, hourUsed: 15)
        let otherAlternative = makeAccount(id: "other", weekUsed: 40, hourUsed: 25)

        let target = AccountRanking.pickAutoSwitchTarget([exhaustedCurrent, otherAlternative, bestAlternative])

        XCTAssertEqual(target?.id, bestAlternative.id)
    }

    func testAutoSwitchTargetIsNilWhenNoCurrentAccount() {
        let accountA = makeAccount(id: "a", weekUsed: 100, hourUsed: 100)
        let accountB = makeAccount(id: "b", weekUsed: 5, hourUsed: 5)

        let target = AccountRanking.pickAutoSwitchTarget([accountA, accountB])

        XCTAssertNil(target)
    }

    func testAutoSwitchTargetIsNilWhenCurrentExhaustedButNoAlternative() {
        let current = makeAccount(id: "current", weekUsed: 100, hourUsed: 100, isCurrent: true)

        let target = AccountRanking.pickAutoSwitchTarget([current])

        XCTAssertNil(target)
    }

    private func makeAccount(id: String, weekUsed: Double, hourUsed: Double, isCurrent: Bool = false) -> AccountSummary {
        AccountSummary(
            id: id,
            label: id,
            email: nil,
            accountID: id,
            planType: nil,
            teamName: nil,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: UsageSnapshot(
                fetchedAt: 0,
                planType: nil,
                fiveHour: UsageWindow(usedPercent: hourUsed, windowSeconds: 5 * 60 * 60, resetAt: nil),
                oneWeek: UsageWindow(usedPercent: weekUsed, windowSeconds: 7 * 24 * 60 * 60, resetAt: nil),
                credits: nil
            ),
            usageError: nil,
            isCurrent: isCurrent
        )
    }
}
