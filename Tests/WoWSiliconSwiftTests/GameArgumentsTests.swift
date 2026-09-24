import XCTest
@testable import WoWSiliconSwift

final class GameArgumentsTests: XCTestCase {
    func testSplitsOnUnquotedWhitespace() throws {
        XCTAssertEqual(try GameArguments.parse("  -console   -uid   wow  "), ["-console", "-uid", "wow"])
    }

    func testEmptyTextProducesNoArguments() throws {
        XCTAssertEqual(try GameArguments.parse("   \n  "), [])
    }

    func testDoubleQuotedValueKeepsSpaces() throws {
        XCTAssertEqual(try GameArguments.parse("-login \"My Name\""), ["-login", "My Name"])
    }

    func testSingleQuotedValueKeepsMetacharacters() throws {
        XCTAssertEqual(try GameArguments.parse("-password 'p@$s`w\\ord'"), ["-password", "p@$s`w\\ord"])
    }

    func testBackslashEscapesQuoteInsideDoubleQuotes() throws {
        XCTAssertEqual(try GameArguments.parse("-password \"a\\\"b\""), ["-password", "a\"b"])
    }

    func testBackslashIsLiteralBeforeOtherCharactersInsideDoubleQuotes() throws {
        XCTAssertEqual(try GameArguments.parse("\"a\\nb\""), ["a\\nb"])
    }

    func testQuotedEmptyValueProducesEmptyArgument() throws {
        XCTAssertEqual(try GameArguments.parse("-realmname \"\""), ["-realmname", ""])
    }

    func testNewlinesSeparateArguments() throws {
        XCTAssertEqual(try GameArguments.parse("-console\n-uid wow"), ["-console", "-uid", "wow"])
    }

    func testUnterminatedQuoteThrows() {
        XCTAssertThrowsError(try GameArguments.parse("-login \"unclosed"))
    }

    func testTrailingBackslashThrows() {
        XCTAssertThrowsError(try GameArguments.parse("-login value\\"))
    }

    func testShellFragmentIsEmptyForNoArguments() {
        XCTAssertEqual(GameArguments.makeShellFragment([]), "")
    }

    func testShellFragmentEscapesSingleQuotes() {
        XCTAssertEqual(GameArguments.makeShellFragment(["it's"]), #"'it'\''s'"#)
    }

    // Confirms the rendered fragment reaches a program as the exact argument list,
    // with no shell expansion, word splitting, or globbing applied to the values.
    func testFragmentReproducesArgumentsThroughShell() throws {
        let arguments = ["-login", "My Name", "-password", "p@$s`w'o\"rd\\*", "-realmname", ""]
        let fragment = GameArguments.makeShellFragment(arguments)

        let result = try ProcessRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "/usr/bin/printf '%s\\n' \(fragment)"],
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = result.stdout.components(separatedBy: "\n").dropLast()
        XCTAssertEqual(Array(lines), arguments)
    }
}
