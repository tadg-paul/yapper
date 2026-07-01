// ABOUTME: Shared test harness that constructs a throwaway install prefix mirroring real yapper topology.
// ABOUTME: Invokes bin/yapper (and bin/yap) via their real wrapper scripts so tests catch install-layout bugs.

import Foundation

/// Captures stdout, stderr, and exit code from a subprocess invocation.
struct YapperRun {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Test harness that builds a throwaway install prefix matching the real
/// Homebrew / make-install layout, then runs the yapper binary through its
/// wrapper scripts.
///
/// ## Why this exists
///
/// yapper ships as a binary in `libexec/yapper` with three Swift resource
/// bundles (`mlx-swift_Cmlx.bundle`, `MisakiSwift_MisakiSwift.bundle`,
/// `ZIPFoundation_ZIPFoundation.bundle`) sitting next to it. End users
/// invoke the binary via thin wrapper scripts at `bin/yapper` and `bin/yap`
/// that `exec` the real libexec binary so `Bundle.main.bundleURL` resolves
/// to `libexec/` and MLX can find its `default.metallib`.
///
/// v0.8.4 shipped with broken install topology (symlinks instead of
/// wrappers) because the test suite at the time spawned the binary directly
/// from DerivedData, never exercising the wrapper indirection. This harness
/// fixes that by construction: every test goes through the same bin/wrapper
/// → libexec/binary chain that real users hit.
///
/// ## Usage
///
/// ```swift
/// private static let harness: YapperProcessHarness = {
///     try! YapperProcessHarness()
/// }()
///
/// @Test("something")
/// func testSomething() throws {
///     let result = try Self.harness.runYapper(args: ["speak", "--dry-run", "test"])
///     #expect(result.exitCode == 0)
/// }
/// ```
///
/// The harness is cheap to construct (symlinks and tiny wrapper scripts,
/// no binary copy) and should be instantiated once per suite as a static.
final class YapperProcessHarness {

    /// The ephemeral install prefix root. Mirrors a real install layout:
    /// `prefix/bin/yapper` (wrapper), `prefix/bin/yap` (wrapper),
    /// `prefix/libexec/yapper` (symlink to real DerivedData binary),
    /// `prefix/libexec/*.bundle` (symlinks to real DerivedData bundles).
    let prefix: URL

    /// Path to the bin/yapper wrapper script users (and tests) invoke.
    let binYapper: URL

    /// Path to the bin/yap wrapper script users (and tests) invoke.
    let binYap: URL

    /// Construct an install prefix in a temp directory and populate it.
    ///
    /// Throws if the DerivedData source binary or any required bundle cannot be
    /// found. The caller should typically trigger `make build` before running
    /// tests that depend on this harness — the `make test-framework` target
    /// already does so.
    init() throws {
        // 1. Locate the source binary and bundles in DerivedData.
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: derivedData.path)) ?? []
        var sourceBuildDir: URL?
        for entry in entries where entry.hasPrefix("yapper-") {
            let candidate = derivedData
                .appendingPathComponent(entry)
                .appendingPathComponent("Build/Products/Debug")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("yapper").path) {
                sourceBuildDir = candidate
                break
            }
        }
        guard let sourceBuildDir else {
            throw HarnessError.sourceBinaryNotFound
        }
        let sourceBinary = sourceBuildDir.appendingPathComponent("yapper")

        let requiredBundles = [
            "mlx-swift_Cmlx.bundle",
            "MisakiSwift_MisakiSwift.bundle",
            "ZIPFoundation_ZIPFoundation.bundle"
        ]
        for bundle in requiredBundles {
            let path = sourceBuildDir.appendingPathComponent(bundle).path
            if !FileManager.default.fileExists(atPath: path) {
                throw HarnessError.sourceBundleMissing(bundle)
            }
        }

        // 2. Build a throwaway install prefix in tmp.
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper-test-harness-\(UUID().uuidString)")
        let bin = prefix.appendingPathComponent("bin")
        let libexec = prefix.appendingPathComponent("libexec")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libexec, withIntermediateDirectories: true)

        // 3. Symlink the binary and bundles into libexec. We use symlinks rather
        // than copies because (a) it's faster, (b) the binary is 41MB per test
        // run would be wasteful, (c) any code change in DerivedData is picked up
        // automatically by the next test run without harness reconstruction, and
        // (d) _NSGetExecutablePath resolves to libexec/yapper either way because
        // the wrapper scripts below `exec` the libexec path explicitly.
        try FileManager.default.createSymbolicLink(
            at: libexec.appendingPathComponent("yapper"),
            withDestinationURL: sourceBinary
        )
        for bundle in requiredBundles {
            try FileManager.default.createSymbolicLink(
                at: libexec.appendingPathComponent(bundle),
                withDestinationURL: sourceBuildDir.appendingPathComponent(bundle)
            )
        }

        // 4. Write wrapper scripts exactly matching the real Homebrew / Makefile
        // install layout. exec'ing libexec/yapper ensures _NSGetExecutablePath
        // resolves to libexec/ so Bundle.main finds the bundles. exec -a yap
        // on the yap wrapper sets argv[0]="yap" so the binary's argv[0] dispatch
        // routes to the speak subcommand.
        let yapperWrapperSource = """
        #!/bin/bash
        exec "\(libexec.path)/yapper" "$@"
        """
        let yapWrapperSource = """
        #!/bin/bash
        exec -a yap "\(libexec.path)/yapper" "$@"
        """
        let binYapper = bin.appendingPathComponent("yapper")
        let binYap = bin.appendingPathComponent("yap")
        try yapperWrapperSource.write(to: binYapper, atomically: true, encoding: .utf8)
        try yapWrapperSource.write(to: binYap, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: binYapper.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: binYap.path
        )

        self.prefix = prefix
        self.binYapper = binYapper
        self.binYap = binYap
    }

    deinit {
        try? FileManager.default.removeItem(at: prefix)
    }

    /// Spawn bin/yapper with the given args and environment. Returns captured output.
    ///
    /// - Parameters:
    ///   - args: Arguments passed to yapper (e.g. `["speak", "--dry-run", "hi"]`).
    ///   - env: Environment variable overrides. Merged on top of the current
    ///     process environment, then `YAPPER_VOICE` is explicitly deleted if
    ///     not provided by the caller (so tests don't leak each other's state
    ///     through the parent shell).
    func runYapper(args: [String], env: [String: String] = [:]) throws -> YapperRun {
        try run(binary: binYapper, args: args, env: env)
    }

    /// Spawn bin/yap (the shortcut wrapper) with the given args and environment.
    func runYap(args: [String], env: [String: String] = [:]) throws -> YapperRun {
        try run(binary: binYap, args: args, env: env)
    }

    private func run(binary: URL, args: [String], env: [String: String]) throws -> YapperRun {
        let proc = Process()
        proc.executableURL = binary
        proc.arguments = args

        var environment = ProcessInfo.processInfo.environment
        environment["YAPPER_VOICE"] = nil
        for (k, v) in env { environment[k] = v }
        proc.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        try proc.run()
        proc.waitUntilExit()

        let out = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let err = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return YapperRun(stdout: out, stderr: err, exitCode: proc.terminationStatus)
    }

    /// Extract the resolved voice name from `yapper speak --dry-run` stdout.
    /// Returns nil if the output contains no `voice:` line.
    static func parseDryRunVoice(_ stdout: String) -> String? {
        for line in stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("voice:") {
                let value = trimmed.dropFirst("voice:".count).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    enum HarnessError: Error, CustomStringConvertible {
        case sourceBinaryNotFound
        case sourceBundleMissing(String)

        var description: String {
            switch self {
            case .sourceBinaryNotFound:
                return "yapper binary not found under DerivedData — run 'make build' first"
            case .sourceBundleMissing(let name):
                return "required bundle missing from DerivedData: \(name) — run 'make build' first"
            }
        }
    }
}
