// ABOUTME: One-off tests for the yap shorthand command (issue #14).
// ABOUTME: Invokes bin/yap via YapperProcessHarness to exercise the real install wrapper and argv[0] dispatch.

import Testing
import Foundation

/// Issue #14: yap is a shorthand for `yapper speak`. Implementation is a bash
/// wrapper at `bin/yap` that uses `exec -a yap` to set argv[0]="yap" while
/// executing the real `libexec/yapper` binary. The binary's own argv[0]
/// dispatch (in Sources/yapper/Yapper.swift) notices argv[0]=="yap" and
/// rewrites the argument list to prepend "speak" before handing off to
/// ArgumentParser.
///
/// ## Why these tests are RT, not OT
///
/// The original tests for #14 were OT-14.1 through OT-14.8 in
/// Tests/one_off/HomebrewFormulaTests.swift — static grep checks on
/// Formula/yapper.rb, Yapper.swift, Makefile, and README.md. Those tests
/// passed while v0.8.4 shipped a broken install topology, because none of
/// them invoked the binary. Per the post-mortem, replaced with runtime
/// tests that invoke bin/yap via the real wrapper.
///
/// Moved from OT to RT because these protect an ongoing behavioural
/// invariant (yap routes to speak) rather than a per-release artefact.
/// Per TESTING.md §"Never renumber", OT-14.1–14.8 IDs are preserved as
/// 🚫 removed on the #14 AC table; new RT-14.x IDs are allocated for
/// these replacements.
@Suite("Issue #14 yap shortcut", .serialized)
struct YapShortcutTests {

    // `nonisolated(unsafe)` matches the pattern used by SpeakCommandTests.engine —
    // the harness is constructed once, all tests in the suite run serially
    // (@Suite(.serialized)), and it's only torn down on process exit.
    private nonisolated(unsafe) static let harness: YapperProcessHarness = {
        do {
            return try YapperProcessHarness()
        } catch {
            fatalError("Failed to construct YapperProcessHarness: \(error)")
        }
    }()

    // AC14.1 + AC14.2 (yap on PATH, equivalent to yapper speak)
    //
    // RT-14.1: Invoking bin/yap with --dry-run routes to the speak subcommand.
    // This is the smallest, most direct test of the argv[0] dispatch: if the
    // wrapper isn't setting argv[0]="yap", or if the Swift dispatch isn't
    // reading it, --dry-run will never produce its characteristic output.
    @Test("RT-14.1: bin/yap --dry-run routes to the speak subcommand via argv[0] dispatch")
    func test_yap_dry_run_routes_to_speak_RT14_1() throws {
        let run = try Self.harness.runYap(args: ["--dry-run", "hello"])

        #expect(run.exitCode == 0,
                "bin/yap --dry-run failed. stdout=\(run.stdout) stderr=\(run.stderr)")

        // Dry-run output is speak-specific. If yap dispatched anywhere else
        // (or crashed, or fell through to the root YapperCLI command) this
        // would not appear.
        #expect(run.stdout.contains("voice:"),
                "bin/yap --dry-run output missing 'voice:' line — dispatch to speak failed")
        #expect(run.stdout.contains("text:   hello"),
                "bin/yap --dry-run output missing text line — argument passthrough failed")
        #expect(run.stdout.contains("(dry run"),
                "bin/yap --dry-run output missing advisory line")
    }

    // RT-14.2: bin/yap passes CLI flags through to the speak subcommand.
    // Verifies that --voice, --speed, etc. are carried across the argv[0]
    // dispatch rewrite correctly.
    @Test("RT-14.2: bin/yap passes --voice and --speed flags through to speak")
    func test_yap_flag_passthrough_RT14_2() throws {
        let run = try Self.harness.runYap(args: [
            "--voice", "bf_emma", "--speed", "1.25", "--dry-run", "the quick brown fox"
        ])

        #expect(run.exitCode == 0,
                "bin/yap with flags failed. stdout=\(run.stdout) stderr=\(run.stderr)")
        #expect(YapperProcessHarness.parseDryRunVoice(run.stdout) == "bf_emma",
                "bin/yap did not propagate --voice to speak")
        #expect(run.stdout.contains("1.25"),
                "bin/yap did not propagate --speed to speak")
        #expect(run.stdout.contains("the quick brown fox"),
                "bin/yap did not propagate the text argument to speak")
    }

    // RT-14.3: bin/yap and bin/yapper speak produce the same resolved voice
    // for the same fixed input (belt-and-braces equivalence check).
    //
    // Uses a fixed --voice so the random-selection path doesn't introduce
    // noise. If both paths resolve to the same voice, the argv[0] dispatch
    // is wired correctly end-to-end.
    @Test("RT-14.3: bin/yap and bin/yapper speak produce equivalent dry-run output")
    func test_yap_equivalent_to_yapper_speak_RT14_3() throws {
        let yapRun = try Self.harness.runYap(
            args: ["--voice", "am_adam", "--dry-run", "equivalence test"]
        )
        let yapperRun = try Self.harness.runYapper(
            args: ["speak", "--voice", "am_adam", "--dry-run", "equivalence test"]
        )

        #expect(yapRun.exitCode == 0)
        #expect(yapperRun.exitCode == 0)

        let yapVoice = YapperProcessHarness.parseDryRunVoice(yapRun.stdout)
        let yapperVoice = YapperProcessHarness.parseDryRunVoice(yapperRun.stdout)
        #expect(yapVoice == "am_adam")
        #expect(yapperVoice == "am_adam")
        #expect(yapVoice == yapperVoice,
                "bin/yap and bin/yapper speak resolved different voices: \(yapVoice ?? "nil") vs \(yapperVoice ?? "nil")")

        // Both runs should contain the same text and advisory line. The
        // formatting is identical because yap is just a relabel of speak.
        #expect(yapRun.stdout.contains("equivalence test"))
        #expect(yapperRun.stdout.contains("equivalence test"))
    }
}
