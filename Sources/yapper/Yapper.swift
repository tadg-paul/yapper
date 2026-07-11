// ABOUTME: CLI entry point for the yapper TTS tool. Dispatches to public subcommands.
// ABOUTME: Also handles the `yap` shorthand via argv[0] inspection when invoked via that symlink.

import ArgumentParser
import Foundation
import YapperKit

struct YapperCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yapper",
        abstract: "Fast, Apple Silicon-native text-to-speech toolkit.",
        version: YapperKit.version,
        subcommands: [SpeakCommand.self, VoicesCommand.self, ConvertCommand.self]
    )
}

@main
enum YapperEntry {
    /// Entry point.
    ///
    /// When invoked directly as `yapper`, hands off to ArgumentParser normally.
    ///
    /// When invoked via the `yap` symlink (installed alongside the main binary by
    /// both Homebrew and `make install`), rewrites the argument list to prepend
    /// `speak` before dispatch — so `yap "hello"` behaves as `yapper speak "hello"`.
    /// The symlink points at this same Mach-O; the switch is purely driven by
    /// `CommandLine.arguments[0]`'s basename.
    ///
    /// Case-insensitive comparison handles macOS's default case-insensitive
    /// filesystem, where a user might type `YAP` or `Yap` and still hit the
    /// same inode.
    static func main() {
        let invocation = (CommandLine.arguments.first.map {
            (($0 as NSString).lastPathComponent)
        } ?? "").lowercased()

        if invocation == "yap" {
            // Rewrite: yap <args...> → speak <args...>
            let rewritten = ["speak"] + CommandLine.arguments.dropFirst()
            YapperCLI.main(Array(rewritten))
        } else {
            YapperCLI.main()
        }
    }
}
