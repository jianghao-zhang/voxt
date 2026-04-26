import XCTest
@testable import Voxt

final class SessionEndFlowTests: XCTestCase {
    func testSessionEndExecutionDecisionAllowsFreshSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            AppDelegate.sessionEndExecutionDecision(
                requestedSessionID: sessionID,
                currentEndingSessionID: nil,
                lastCompletedSessionEndSessionID: nil
            ),
            .execute
        )
    }

    func testSessionEndExecutionDecisionRejectsDuplicateInFlightSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            AppDelegate.sessionEndExecutionDecision(
                requestedSessionID: sessionID,
                currentEndingSessionID: sessionID,
                lastCompletedSessionEndSessionID: nil
            ),
            .skipDuplicateInFlight
        )
    }

    func testSessionEndExecutionDecisionRejectsAlreadyCompletedSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            AppDelegate.sessionEndExecutionDecision(
                requestedSessionID: sessionID,
                currentEndingSessionID: nil,
                lastCompletedSessionEndSessionID: sessionID
            ),
            .skipAlreadyCompleted
        )
    }
}
