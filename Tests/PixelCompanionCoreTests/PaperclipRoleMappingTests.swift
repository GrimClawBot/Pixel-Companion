import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipRoleMappingTests: XCTestCase {
    func testStructuredBackendRoleIsPreservedWithoutGuessingACompanyDepartment() throws {
        let company = PaperclipCompany(id: "org", name: "Company", status: "active")
        let decoder = JSONDecoder()
        let first = try decoder.decode(
            PaperclipAgentResponse.self,
            from: Data(#"{"id":"atlas","name":"Atlas","role":"ceo","status":"idle"}"#.utf8)
        )
        let second = try decoder.decode(
            PaperclipAgentResponse.self,
            from: Data(#"{"id":"emma","name":"Emma","status":"idle"}"#.utf8)
        )
        let input = PaperclipMappingInput(
            companies: [company], company: company,
            dashboard: .init(costs: .init(monthSpendCents: 0, monthBudgetCents: 0)),
            agents: [first, second], issues: [], approvals: [], runs: []
        )
        let sessions = PaperclipMapper.map(input).agentSessions
        XCTAssertEqual(sessions.first { $0.agentID == "atlas" }?.agentRole, "ceo")
        XCTAssertNil(sessions.first { $0.agentID == "emma" }?.agentRole)
    }
}
