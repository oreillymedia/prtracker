import Testing
import Foundation
@testable import PRTracker

@Suite struct RepoDTOTests {
    @Test func decodesFullName() throws {
        let json = #"{"full_name":"oreilly/spark-ios","private":true,"default_branch":"main"}"#
        let dto = try JSONDecoder().decode(RepoDTO.self, from: Data(json.utf8))
        #expect(dto.full_name == "oreilly/spark-ios")
    }
}
