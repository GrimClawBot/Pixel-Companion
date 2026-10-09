import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipRoleMappingTests: XCTestCase {
    func testReportedManagerLinkIsPreservedFromPaperclipAgentWithoutGuessing() throws {
        let decoder = JSONDecoder()
        let company = PaperclipCompany(id: "org", name: "Company", status: "active")
        let examples = [
            #"{"id":"atlas","name":"Atlas","role":"ceo","status":"idle","reportsTo":null}"#,
            #"{"id":"emma","name":"Emma","role":"researcher","status":"running","reportsTo":"atlas"}"#,
            #"{"id":"ethan","name":"Ethan","status":"idle"}"#,
            #"{"id":"x","name":"X","status":"idle","reportsTo":{"id":"atlas"}}"#
        ]
        let agents = try examples.map {
            try decoder.decode(PaperclipAgentResponse.self, from: Data($0.utf8))
        }
        let input = PaperclipMappingInput(
            companies: [company], company: company,
            dashboard: .init(costs: .init(monthSpendCents: 0, monthBudgetCents: 0)),
            agents: agents, issues: [], approvals: [], runs: []
        )
        let sessions = PaperclipMapper.map(input).agentSessions
        XCTAssertEqual(sessions.first { $0.agentID == "emma" }?.managerAgentID, "atlas")
        XCTAssertEqual(sessions.first { $0.agentID == "emma" }?.agentRole, "researcher")
        XCTAssertNil(sessions.first { $0.agentID == "atlas" }?.managerAgentID)
        XCTAssertNil(sessions.first { $0.agentID == "ethan" }?.managerAgentID)
        XCTAssertNil(sessions.first { $0.agentID == "x" }?.managerAgentID)
    }

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
