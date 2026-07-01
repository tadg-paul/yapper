// ABOUTME: Static structural tests for Formula/yapper.rb and release/verify scripts.
// ABOUTME: Covers OT-11.7/8/11–18 (issue #11) and OT-13.4/5/8–14/16 (issue #13).
//
// Removed tests (IDs preserved per TESTING.md §"Never renumber"):
//   🚫 OT-11.2  — Formula referenced a tagged source release (now points at
//                 a binary tarball). Superseded by OT-11.14.
//   🚫 OT-11.4  — Formula declared Xcode/Metal deps. No longer applicable:
//                 prebuilt binary needs no Xcode. Superseded by OT-11.17.
//   🚫 OT-11.5  — Formula caveats mentioned Xcode/Metal. Superseded by
//                 prebuilt-binary caveat text.
//   🚫 OT-11.9  — Formula declared resource "model" + "voices" AND a xcodebuild
//                 install block. Split into OT-11.15 (model/voices only) and
//                 OT-11.16 (no build step).
//   🚫 OT-11.10 — Formula install block used xcodebuild. Replaced by OT-11.16.

import Testing
import Foundation

@Suite("Issue #11 Homebrew formula structure")
struct HomebrewFormulaTests {

    private static let projectRoot: URL = {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "/Users/tigger/code/tigoss/yapper")
    }()

    private static func read(_ relativePath: String) throws -> String {
        let url = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // OT-11.7: release.sh performs tag + version bump
    @Test("OT-11.7: release.sh bumps version and creates tag")
    func releaseScriptTagsAndBumps() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("git -C \"${PROJECT_ROOT}\" tag -a \"${TAG}\""),
                "release.sh must create an annotated git tag")
        #expect(script.contains("bump_version"),
                "release.sh must bump version")
        #expect(script.contains("Version.swift"),
                "release.sh must update Version.swift")
    }

    // OT-11.8: release.sh writes Formula and mirrors to tap
    @Test("OT-11.8: release.sh writes Formula and mirrors to tap")
    func releaseScriptUpdatesFormula() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("Formula/yapper.rb"),
                "release.sh must write Formula/yapper.rb")
        #expect(script.contains("tigger04/homebrew-tap"),
                "release.sh must push formula to the tap repo")
    }

    // OT-11.11: release-models.sh filters English voices and uploads
    @Test("OT-11.11: release-models.sh filters English voices and uploads to models-v1")
    func releaseModelsScriptStructure() throws {
        let script = try Self.read("scripts/release-models.sh")
        #expect(script.contains("models-v1"))
        #expect(script.contains("a[fm]_*.safetensors"))
        #expect(script.contains("b[fm]_*.safetensors"))
        #expect(script.contains("voices.tar.gz"))
        #expect(script.contains("kokoro-v1_0.safetensors"))
        #expect(script.contains("gh release"))
    }

    // OT-11.12: Makefile wiring
    @Test("OT-11.12: Makefile exposes release and release-models targets")
    func makefileExposesReleaseTargets() throws {
        let makefile = try Self.read("Makefile")
        #expect(makefile.contains("release-models:"))
        #expect(makefile.contains("release:"))
        #expect(makefile.contains("scripts/release-models.sh"))
        #expect(makefile.contains("scripts/release.sh"))
    }

    // OT-11.13: release.sh builds, signs, tars, and uploads the binary
    // (ad-hoc signing assertion replaced in #13 by Developer ID signing; see OT-13.8)
    @Test("OT-11.13: release.sh builds, signs, tars, and uploads the binary")
    func releaseScriptBuildsAndPackagesBinary() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("xcodebuild build"),
                "release.sh must build the release binary with xcodebuild")
        #expect(script.contains("codesign --force --sign"),
                "release.sh must sign the binary")
        #expect(script.contains("tar -czf"),
                "release.sh must tar the binary + bundles")
        #expect(script.contains("gh release create"),
                "release.sh must create the GH release")
        #expect(script.contains("yapper-macos-arm64.tar.gz"),
                "release.sh must name the asset yapper-macos-arm64.tar.gz")
    }

    // OT-11.14: Formula main url targets the code release tag's binary asset
    @Test("OT-11.14: Formula url targets the code release binary asset")
    func formulaUrlTargetsBinaryAsset() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("yapper-macos-arm64.tar.gz"),
                "Formula url must reference the binary tarball asset")
        #expect(formula.range(of: #"releases/download/v\d+\.\d+\.\d+/yapper-macos-arm64\.tar\.gz"#,
                              options: .regularExpression) != nil,
                "Formula url must use a tagged code release (vX.Y.Z), not HEAD")
    }

    // OT-11.15: Formula declares model and voices resources
    @Test("OT-11.15: Formula declares model and voices resources")
    func formulaDeclaresResources() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("resource \"model\""))
        #expect(formula.contains("resource \"voices\""))
        #expect(formula.contains("kokoro-v1_0.safetensors"))
        #expect(formula.contains("voices.tar.gz"))
        #expect(formula.contains("models-v1"))
    }

    // OT-11.16: Formula install block has no build step
    @Test("OT-11.16: Formula install block has no xcodebuild or swift build")
    func formulaInstallBlockHasNoBuildStep() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(!formula.contains("xcodebuild"),
                "Formula must not invoke xcodebuild")
        #expect(!formula.contains("\"swift\""),
                "Formula must not invoke swift build/package resolve")
        #expect(formula.contains("libexec.install \"yapper\""),
                "Formula must install the prebuilt binary into libexec")
        #expect(formula.contains("libexec.install Dir[\"*.bundle\"]"),
                "Formula must install resource bundles alongside the binary")
    }

    // OT-11.17: Formula declares runtime dependency on ffmpeg only
    @Test("OT-11.17: Formula declares ffmpeg runtime dep and no Xcode dep")
    func formulaDeclaresRuntimeDepsOnly() throws {
        let formula = try Self.read("Formula/yapper.rb")
        #expect(formula.contains("depends_on \"ffmpeg\""))
        #expect(formula.contains("depends_on :macos"))
        #expect(formula.contains("depends_on arch: :arm64"))
        #expect(!formula.contains("depends_on :xcode"),
                "Prebuilt binary formula must not require Xcode")
    }

    // OT-11.18: release.sh signs the binary with hardened runtime
    // (originally "ad-hoc signs", reworded to reflect the Developer ID pivot in #13)
    @Test("OT-11.18: release.sh signs binary with hardened runtime")
    func releaseScriptSignsWithHardenedRuntime() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("codesign --force --sign"),
                "release.sh must sign the binary via codesign")
        #expect(script.contains("--options runtime"),
                "release.sh must enable hardened runtime")
        #expect(script.contains("--timestamp"),
                "release.sh must include a secure timestamp")
    }

    // ---------- Issue #13: Developer ID signing + notarisation ----------

    // OT-13.4: release.sh post-upload confirms the asset is on the release
    @Test("OT-13.4: release.sh re-downloads the uploaded asset via gh release download")
    func releaseScriptDownloadsUploadedAssetForVerification() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("gh release download"),
                "release.sh must re-download the uploaded asset post-upload")
        #expect(script.contains("yapper-macos-arm64.tar.gz"),
                "release.sh must reference the tarball asset by name")
    }

    // OT-13.5: release.sh runs verify-signature.sh on the re-downloaded asset
    @Test("OT-13.5: release.sh verifies the downloaded asset's codesign envelope")
    func releaseScriptVerifiesDownloadedAsset() throws {
        let script = try Self.read("scripts/release.sh")
        // The script calls verify-signature.sh twice: once pre-upload on the staging dir,
        // and once post-upload on the downloaded tarball extracted into verify_dir.
        let matches = script.components(separatedBy: "verify-signature.sh").count - 1
        #expect(matches >= 2,
                "release.sh must call verify-signature.sh both pre-upload and post-upload")
    }

    // OT-13.8: release.sh signs with an auto-discovered Developer ID identity
    @Test("OT-13.8: release.sh signs with Developer ID identity (auto-discovered)")
    func releaseScriptSignsWithDeveloperID() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("Developer ID Application"),
                "release.sh must grep for a Developer ID Application identity")
        #expect(script.contains("security find-identity"),
                "release.sh must auto-discover the signing identity from the keychain")
        #expect(script.contains("codesign --force --sign \"${IDENTITY}\""),
                "release.sh must pass the discovered identity to codesign")
        #expect(!script.contains("codesign --force --sign - "),
                "release.sh must not use ad-hoc signing (--sign -) anywhere")
    }

    // OT-13.9: release.sh submits to notarytool with the yapper-notary profile and --wait
    @Test("OT-13.9: release.sh submits to notarytool and checks status Accepted")
    func releaseScriptSubmitsToNotarytool() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("xcrun notarytool submit"),
                "release.sh must submit to notarytool")
        #expect(script.contains("--keychain-profile \"${NOTARY_PROFILE}\""),
                "release.sh must use the yapper-notary keychain profile")
        #expect(script.contains("--wait"),
                "release.sh must wait for notarisation to complete")
        #expect(script.contains("status: Accepted"),
                "release.sh must check the notary status is Accepted")
    }

    // OT-13.10: release.sh aborts if keychain profile or cert is missing
    @Test("OT-13.10: release.sh fails fast on misconfigured signing environment")
    func releaseScriptFailsFastOnMisconfig() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("discover_identity"),
                "release.sh must have an identity discovery function")
        #expect(script.contains("verify_notary_profile"),
                "release.sh must have a notarytool profile verification function")
        #expect(script.contains("No 'Developer ID Application' certificate found"),
                "release.sh must produce a clear error when no Developer ID cert is installed")
        #expect(script.contains("notarytool keychain profile") &&
                script.contains("not configured"),
                "release.sh must produce a clear error when the notarytool profile is missing")
    }

    // OT-13.11: release.sh runs verify-signature.sh as a pre-upload gate
    @Test("OT-13.11: release.sh runs verify-signature.sh as a pre-upload gate")
    func releaseScriptPreUploadVerification() throws {
        let script = try Self.read("scripts/release.sh")
        #expect(script.contains("Verifying signed artefact"),
                "release.sh must have a pre-upload verification step")
    }

    // OT-13.12: verify-signature.sh checks authority and timestamp
    @Test("OT-13.12: verify-signature.sh checks authority and secure timestamp")
    func verifyScriptChecksAuthorityAndTimestamp() throws {
        let script = try Self.read("scripts/verify-signature.sh")
        #expect(script.contains("Authority=Developer ID Application:"),
                "verify-signature.sh must assert the authority is a Developer ID")
        #expect(script.contains("Timestamp="),
                "verify-signature.sh must assert a secure timestamp is present")
    }

    // OT-13.13: verify-signature.sh checks hardened runtime
    @Test("OT-13.13: verify-signature.sh checks hardened runtime flag")
    func verifyScriptChecksHardenedRuntime() throws {
        let script = try Self.read("scripts/verify-signature.sh")
        #expect(script.contains("runtime"),
                "verify-signature.sh must check for hardened runtime flag")
        #expect(script.contains("codesign --display"),
                "verify-signature.sh must inspect the signature for flags")
    }

    // OT-13.14: verify-signature.sh checks bundles are signed inside-out
    @Test("OT-13.14: verify-signature.sh checks bundles are signed inside-out")
    func verifyScriptChecksInsideOutSigning() throws {
        let script = try Self.read("scripts/verify-signature.sh")
        #expect(script.contains("_CodeSignature"),
                "verify-signature.sh must assert each bundle has its own _CodeSignature/")
        for bundle in ["mlx-swift_Cmlx.bundle",
                       "MisakiSwift_MisakiSwift.bundle",
                       "ZIPFoundation_ZIPFoundation.bundle"] {
            #expect(script.contains(bundle),
                    "verify-signature.sh must verify \(bundle)")
        }
    }

    // OT-13.16: 🚫 removed — spctl --assess is the wrong tool for bare Mach-O binaries.
    // It requires a .app bundle and reports 'does not seem to be an app' otherwise.
    // Notarisation acceptance is verified via notarytool 'status: Accepted' (OT-13.9),
    // and signature validity is verified via codesign (OT-13.12, 13.13). The end-user
    // Gatekeeper path is exercised in UT-13.2 and UT-13.3.
}

// Issue #14 yap shortcut tests:
//   OT-14.1 through OT-14.8 DELETED from this suite 2026-04-05. They were
//   static grep checks on Formula/yapper.rb, scripts/release.sh,
//   Sources/yapper/Yapper.swift, Makefile, and README.md. None of them
//   invoked the yapper binary. They gave false confidence: v0.8.4 passed
//   every one of these tests while shipping a broken install topology.
//
// Replacement tests: RT-14.1, RT-14.2, RT-14.3 in
// Tests/one_off/YapperKitIntegration/YapShortcutTests.swift, which invoke the
// real bin/yap wrapper via YapperProcessHarness — the same harness as the
// rewritten RT-15.x suite.
//
// Per TESTING.md §"Never renumber", OT-14.1–14.8 IDs are preserved as
// 🚫 removed on issue #14's AC table. They are not recycled.
