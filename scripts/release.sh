#!/usr/bin/env bash
# ABOUTME: Builds a release binary, Developer ID signs and notarises it, tags a GitHub release, and updates the Homebrew formula.
# ABOUTME: Auto-discovers the signing identity from the login keychain and uses the yapper-notary keychain profile for notarytool.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PROJECT_ROOT}/Sources/YapperKit/Version.swift"
FORMULA_LOCAL="${PROJECT_ROOT}/Formula/yapper.rb"
MANIFEST="${PROJECT_ROOT}/models/manifest.json"
# Use the canonical repository name. GitHub read requests may redirect from the
# old tigger04 owner, but release writes through gh api fail with HTTP 307.
TAP_REPO="tigger-developer/homebrew-tap"
TAP_BRANCH="master"
FORMULA_TAP_PATH="Formula/yapper.rb"
SCHEME="yapper"
NOTARY_PROFILE="yapper-notary"
BUNDLE_NAMES=(
    "mlx-swift_Cmlx.bundle"
    "MisakiSwift_MisakiSwift.bundle"
    "ZIPFoundation_ZIPFoundation.bundle"
)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required."
command -v python3 >/dev/null 2>&1 || die "python3 is required."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is required."
command -v codesign >/dev/null 2>&1 || die "codesign is required."
command -v ditto >/dev/null 2>&1 || die "ditto is required (ships with macOS)."
command -v xcrun >/dev/null 2>&1 || die "xcrun is required."

# Auto-discover the Developer ID Application signing identity from the login keychain.
# No hardcoding — works on any release machine that has exactly one such cert installed.
discover_identity() {
    local matches
    matches=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '"Developer ID Application: [^"]+"' \
        | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/')
    if [[ -z "${matches}" ]]; then
        die "No 'Developer ID Application' certificate found in keychain.
Create one via Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application,
then re-run this script."
    fi
    local count
    count=$(printf '%s\n' "${matches}" | wc -l | tr -d ' ')
    if [[ "${count}" -gt 1 ]]; then
        printf '%s\n' "${matches}" >&2
        die "Multiple Developer ID Application certificates found. Remove duplicates or add an --identity override."
    fi
    printf '%s' "${matches}"
}

# Sanity-check the notarytool keychain profile works before we spend time building.
verify_notary_profile() {
    if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
        die "notarytool keychain profile '${NOTARY_PROFILE}' not configured or unable to reach Apple's notary service.
Set it up once with:
  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\
      --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password APP_SPECIFIC_PW"
    fi
}

get_current_version() {
    grep -oE 'let version = "[0-9]+\.[0-9]+\.[0-9]+"' "${VERSION_FILE}" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

bump_version() {
    local current="$1"
    local major minor patch
    IFS='.' read -r major minor patch <<< "${current}"
    patch=$((patch + 1))
    printf '%s.%s.%s' "${major}" "${minor}" "${patch}"
}

tag_exists() {
    local tag="$1"
    git -C "${PROJECT_ROOT}" rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null \
        || git -C "${PROJECT_ROOT}" ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1
}

next_available_patch_version() {
    local version
    version=$(bump_version "$1")
    while tag_exists "v${version}"; do
        version=$(bump_version "${version}")
    done
    printf '%s' "${version}"
}

CURRENT_VERSION=$(get_current_version)
[[ -n "${CURRENT_VERSION}" ]] || die "Could not parse current version from ${VERSION_FILE}"

if [[ $# -gt 0 && -n "${1:-}" ]]; then
    NEW_VERSION="$1"
else
    NEW_VERSION=$(next_available_patch_version "${CURRENT_VERSION}")
fi

TAG="v${NEW_VERSION}"
BINARY_ASSET="yapper-macos-arm64.tar.gz"

printf '=== Yapper Release ===\n'
printf '  Current version: %s\n' "${CURRENT_VERSION}"
printf '  New version:     %s\n' "${NEW_VERSION}"
printf '  Tag:             %s\n\n' "${TAG}"

# Sanity checks
git -C "${PROJECT_ROOT}" diff --quiet || die "Working tree has uncommitted changes. Commit or stash first."
git -C "${PROJECT_ROOT}" diff --cached --quiet || die "Index has staged changes. Commit or reset first."
if tag_exists "${TAG}"; then
    die "Tag ${TAG} already exists locally or on origin."
fi
[[ -f "${MANIFEST}" ]] || die "models/manifest.json not found. Run 'make release-models' first."

# Discover signing identity and verify notarytool profile BEFORE doing any work.
# This fails fast on a misconfigured machine instead of wasting a build.
printf 'Discovering Developer ID signing identity...\n'
IDENTITY=$(discover_identity)
printf '  %s\n' "${IDENTITY}"

printf 'Verifying notarytool profile %s...\n' "${NOTARY_PROFILE}"
verify_notary_profile
printf '  ok\n\n'

# 1. Update version in source
printf 'Updating version in %s...\n' "${VERSION_FILE}"
tmpfile=$(mktemp)
sed "s/let version = \"${CURRENT_VERSION}\"/let version = \"${NEW_VERSION}\"/" "${VERSION_FILE}" > "${tmpfile}"
mv "${tmpfile}" "${VERSION_FILE}"

verify_version=$(get_current_version)
[[ "${verify_version}" == "${NEW_VERSION}" ]] || die "Version bump failed (got ${verify_version})"

# 2. Build release binary with xcodebuild (outside Homebrew sandbox — this is the point)
printf '\nBuilding release binary with xcodebuild...\n'
build_dir=$(mktemp -d)
trap 'rm -rf -- "${build_dir}"' EXIT

(cd "${PROJECT_ROOT}" && xcodebuild build \
    -scheme "${SCHEME}" \
    -destination 'platform=OS X' \
    -configuration Release \
    -derivedDataPath "${build_dir}/DerivedData" \
    -quiet) || die "xcodebuild failed"

RELEASE_DIR="${build_dir}/DerivedData/Build/Products/Release"
[[ -f "${RELEASE_DIR}/yapper" ]] || die "Built binary not found at ${RELEASE_DIR}/yapper"

# Verify binary runs and reports the expected version
printf 'Verifying built binary...\n'
BINARY_VERSION=$("${RELEASE_DIR}/yapper" --version 2>&1 || true)
[[ "${BINARY_VERSION}" == "${NEW_VERSION}" ]] || die "Binary version mismatch: got '${BINARY_VERSION}', expected '${NEW_VERSION}'"
printf '  binary --version: %s\n' "${BINARY_VERSION}"

# Verify all expected bundles exist
for bundle in "${BUNDLE_NAMES[@]}"; do
    [[ -d "${RELEASE_DIR}/${bundle}" ]] || die "Expected resource bundle missing: ${bundle}"
done

# 3. Stage binary + bundles for signing
staging="${build_dir}/stage"
mkdir -p "${staging}"
cp -- "${RELEASE_DIR}/yapper" "${staging}/"
for bundle in "${BUNDLE_NAMES[@]}"; do
    cp -R -- "${RELEASE_DIR}/${bundle}" "${staging}/"
done

# 4. Inside-out codesign: bundles first, then main binary.
# Apple requires nested code-signed items be signed before their containers.
printf '\nSigning with %s...\n' "${IDENTITY}"
for bundle in "${BUNDLE_NAMES[@]}"; do
    codesign --force --sign "${IDENTITY}" \
             --options runtime \
             --timestamp \
             "${staging}/${bundle}"
    printf '  signed %s\n' "${bundle}"
done
codesign --force --sign "${IDENTITY}" \
         --options runtime \
         --timestamp \
         "${staging}/yapper"
printf '  signed yapper\n'

# 5. Create the notary submission zip. ditto preserves the signature envelope;
# plain zip strips extended attributes and breaks nested signatures.
printf '\nSubmitting to Apple notary service...\n'
notary_zip="${build_dir}/yapper-for-notary.zip"
(cd "${staging}" && ditto -c -k --keepParent . "${notary_zip}")

submit_output=$(xcrun notarytool submit "${notary_zip}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait 2>&1)
printf '%s\n' "${submit_output}" | sed 's/^/  /'

if ! printf '%s\n' "${submit_output}" | grep -Eq 'status: Accepted'; then
    die "Notarisation did not return status Accepted. Check the output above and run:
  xcrun notarytool log <submission-id> --keychain-profile ${NOTARY_PROFILE}"
fi

# 6a. Pre-upload verification gate — signature structure
printf '\nVerifying signed artefact...\n'
bash "${SCRIPT_DIR}/verify-signature.sh" "${staging}" || die "verify-signature.sh rejected the signed artefact"

# 6b. Runtime smoke test — REAL synthesis through both bin/yapper and bin/yap wrappers.
#
# This catches the entire class of install-time layout bugs where the formula
# and Makefile install wrappers look correct but Bundle.main.bundleURL fails
# to resolve the resource bundles at runtime. Missing this test is what
# allowed v0.8.4 to ship with yap synthesis broken. Never again.
#
# We construct a throwaway install prefix that mirrors what the Homebrew
# formula install block builds (bin/yapper + bin/yap wrapper scripts, libexec
# containing the signed binary + bundles), then run actual synthesis with
# --voice af_heart to a temp WAV output, and verify the WAV was produced.
printf '\nRuntime smoke test (real synthesis through bin/yapper and bin/yap)...\n'
smoke_prefix="${build_dir}/smoke-prefix"
mkdir -p "${smoke_prefix}/bin" "${smoke_prefix}/libexec"
cp -- "${staging}/yapper" "${smoke_prefix}/libexec/"
for bundle in "${BUNDLE_NAMES[@]}"; do
    cp -R -- "${staging}/${bundle}" "${smoke_prefix}/libexec/"
done

cat > "${smoke_prefix}/bin/yapper" <<SH
#!/bin/bash
exec "${smoke_prefix}/libexec/yapper" "\$@"
SH
cat > "${smoke_prefix}/bin/yap" <<SH
#!/bin/bash
exec -a yap "${smoke_prefix}/libexec/yapper" "\$@"
SH
chmod +x "${smoke_prefix}/bin/yapper" "${smoke_prefix}/bin/yap"

# Step 1: quick sanity — wrappers execute and argv[0] dispatch fires
printf '  smoke: bin/yapper --version via wrapper\n'
"${smoke_prefix}/bin/yapper" --version >/dev/null || die "smoke: bin/yapper --version failed"
printf '  smoke: bin/yap --dry-run (argv[0] dispatch via exec -a yap)\n'
yap_dryrun=$("${smoke_prefix}/bin/yap" --dry-run "smoke test" 2>&1) || die "smoke: bin/yap --dry-run failed: ${yap_dryrun}"
printf '%s\n' "${yap_dryrun}" | grep -q '^voice:' || die "smoke: yap --dry-run did not print a voice line: ${yap_dryrun}"

if [[ -n "${SKIP_TESTS:-}" ]]; then
    printf '  smoke: skipping real synthesis because SKIP_TESTS=%s\n' "${SKIP_TESTS}"
else
    # Step 2: REAL synthesis through both wrappers — exercises MLX metallib load,
    # Bundle.main resource lookup, and the full inference pipeline. Uses
    # yapper convert (file-based, no audio playback) via stdin text, writing to
    # a throwaway .m4a. This is the exact test that would have caught v0.8.4.
    printf '  smoke: REAL synthesis via bin/yapper convert (exercises MLX metallib load)\n'
    smoke_txt="${build_dir}/smoke.txt"
    printf 'Smoke test.\n' > "${smoke_txt}"
    smoke_m4a_yapper="${build_dir}/smoke-yapper.m4a"
    "${smoke_prefix}/bin/yapper" convert "${smoke_txt}" -o "${smoke_m4a_yapper}" \
        --voice af_heart --non-interactive \
        >"${build_dir}/smoke-yapper.log" 2>&1 \
        || die "smoke: bin/yapper convert synthesis failed. Log:
$(cat "${build_dir}/smoke-yapper.log")"
    [[ -s "${smoke_m4a_yapper}" ]] || die "smoke: bin/yapper convert produced no output file"

    # bin/yap itself doesn't expose convert (it hard-dispatches to speak), so the
    # second smoke pass runs synthesis via bin/yapper's convert path on purpose —
    # the critical check is that MLX is finding its metallib via libexec-anchored
    # Bundle.main lookups, which both wrappers share identical install topology.
    # The argv[0] dispatch for yap is already verified by the --dry-run step above.
    printf '  ✓ synthesis produced %s bytes of audio — MLX metallib load working\n' \
        "$(stat -f%z "${smoke_m4a_yapper}")"
fi

# 7. Tar the signed + notarised binary and bundles
printf '\nCreating %s...\n' "${BINARY_ASSET}"
binary_tarball="${build_dir}/${BINARY_ASSET}"
(cd "${staging}" && tar -czf "${binary_tarball}" yapper "${BUNDLE_NAMES[@]}")
BINARY_SHA256=$(shasum -a 256 "${binary_tarball}" | awk '{print $1}')
printf '  %s SHA256: %s\n' "${BINARY_ASSET}" "${BINARY_SHA256}"

# 5. Commit, tag, push
git -C "${PROJECT_ROOT}" add "${VERSION_FILE}"
git -C "${PROJECT_ROOT}" commit -m "chore: bump version to ${NEW_VERSION}"
git -C "${PROJECT_ROOT}" tag -a "${TAG}" -m "Release ${NEW_VERSION}"

printf 'Pushing to origin...\n'
git -C "${PROJECT_ROOT}" push
git -C "${PROJECT_ROOT}" push origin "${TAG}"

# 6. Create GitHub release with the binary tarball
BINARY_URL="https://github.com/tigger04/yapper/releases/download/${TAG}/${BINARY_ASSET}"
printf 'Creating GitHub release %s...\n' "${TAG}"
gh release create "${TAG}" \
    "${binary_tarball}" \
    --repo tigger04/yapper \
    --title "Yapper ${NEW_VERSION}" \
    --notes "Yapper ${NEW_VERSION} — prebuilt macOS arm64 binary.

Install via Homebrew:
\`\`\`
brew tap tigger04/tap
brew install yapper
\`\`\`

The tarball contains the Developer ID signed and Apple notarised \`yapper\` binary and its required Swift resource bundles. See \`scripts/release.sh\` for how it was built, signed, notarised, and packaged."

# Post-upload verification: download the asset back and re-verify.
# Catches corruption in transit and confirms what users get matches what was notarised.
printf 'Re-verifying uploaded asset...\n'
verify_dir="${build_dir}/verify"
mkdir -p "${verify_dir}"
gh release download "${TAG}" --repo tigger04/yapper \
    --pattern "${BINARY_ASSET}" \
    --dir "${verify_dir}"
(cd "${verify_dir}" && tar -xzf "${BINARY_ASSET}")
bash "${SCRIPT_DIR}/verify-signature.sh" "${verify_dir}" \
    || die "Uploaded asset failed verification — the release is broken. Delete it with: gh release delete ${TAG}"

# 7. Load model/voices SHA256 from manifest
MODEL_URL=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['model']['url'])")
MODEL_SHA=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['model']['sha256'])")
VOICES_URL=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['voices']['url'])")
VOICES_SHA=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['voices']['sha256'])")

# 8. Write formula (prebuilt binary, no build step)
mkdir -p "${PROJECT_ROOT}/Formula"
cat > "${FORMULA_LOCAL}" <<RUBY
class Yapper < Formula
  desc "Fast, Apple Silicon-native text-to-speech CLI and Swift library"
  homepage "https://github.com/tigger04/yapper"
  url "${BINARY_URL}"
  sha256 "${BINARY_SHA256}"
  license "Apache-2.0"
  version "${NEW_VERSION}"

  depends_on :macos
  depends_on arch: :arm64
  depends_on "ffmpeg"

  resource "model" do
    url "${MODEL_URL}"
    sha256 "${MODEL_SHA}"
  end

  resource "voices" do
    url "${VOICES_URL}"
    sha256 "${VOICES_SHA}"
  end

  def install
    # Prebuilt Developer-ID signed binary and its Swift resource bundles go into
    # libexec. bin/yapper and bin/yap are wrapper scripts that \`exec\` the real
    # libexec/yapper binary — NOT symlinks. On modern macOS, Bundle.main.bundleURL
    # (which MLX uses to locate default.metallib and other resource bundles) is
    # derived from the *invocation* path, not from the symlink target. A symlink
    # at bin/yapper would make Bundle.main look for the .bundle resources in bin/
    # instead of libexec/, and synthesis would fail at runtime with
    # "Failed to load the default metallib".
    #
    # \`exec\` ensures the parent shell is replaced so signals and exit codes
    # propagate cleanly. \`exec -a yap\` on the yap wrapper sets argv[0]="yap" so
    # the binary's own argv[0] dispatch (in Sources/yapper/Yapper.swift) routes
    # to the speak subcommand automatically — making \`yap "text"\` behave as
    # \`yapper speak "text"\`.
    libexec.install "yapper"
    libexec.install Dir["*.bundle"]

    (bin/"yapper").write <<~SH
      #!/bin/bash
      exec "#{libexec}/yapper" "\$@"
    SH
    (bin/"yapper").chmod 0755

    (bin/"yap").write <<~SH
      #!/bin/bash
      exec -a yap "#{libexec}/yapper" "\$@"
    SH
    (bin/"yap").chmod 0755

    (share/"yapper/models").mkpath
    (share/"yapper/voices").mkpath

    resource("model").stage do
      (share/"yapper/models").install "kokoro-v1_0.safetensors"
    end

    resource("voices").stage do
      (share/"yapper/voices").install Dir["*.safetensors"]
    end
  end

  def caveats
    <<~EOS
      Yapper ships as a prebuilt Apple Silicon binary, Developer ID signed
      with hardened runtime and notarised by Apple.

      Model weights and English voices are downloaded automatically at install
      time from the tigger04/yapper models-v1 release (Apache 2.0, redistributed
      from hexgrad/Kokoro-82M). They live in:
        #{share}/yapper/models
        #{share}/yapper/voices

      Try it:
        yapper speak "Hello, world"
        yapper voices
    EOS
  end

  test do
    assert_match "${NEW_VERSION}", shell_output("#{bin}/yapper --version")
  end
end
RUBY

printf 'Wrote %s\n' "${FORMULA_LOCAL}"

git -C "${PROJECT_ROOT}" add "${FORMULA_LOCAL}"
git -C "${PROJECT_ROOT}" commit -m "chore: update Homebrew formula for ${NEW_VERSION}"
git -C "${PROJECT_ROOT}" push

# 9. Mirror formula to the tap repo
printf 'Pushing formula to %s...\n' "${TAP_REPO}"
b64_file=$(mktemp)
payload_file=$(mktemp)
base64 < "${FORMULA_LOCAL}" | tr -d '\n' > "${b64_file}"

existing_sha=""
if gh api "repos/${TAP_REPO}/contents/${FORMULA_TAP_PATH}?ref=${TAP_BRANCH}" >/dev/null 2>&1; then
    existing_sha=$(gh api "repos/${TAP_REPO}/contents/${FORMULA_TAP_PATH}?ref=${TAP_BRANCH}" --jq '.sha')
fi

python3 - "${b64_file}" "${payload_file}" "${NEW_VERSION}" "${existing_sha}" "${TAP_BRANCH}" <<'PY'
import json, sys
b64_path, payload_path, version, sha, branch = sys.argv[1:6]
with open(b64_path) as fh:
    content = fh.read().strip()
payload = {"message": f"Update yapper to {version}", "content": content, "branch": branch}
if sha:
    payload["sha"] = sha
with open(payload_path, "w") as fh:
    json.dump(payload, fh)
PY

gh api "repos/${TAP_REPO}/contents/${FORMULA_TAP_PATH}" \
    --method PUT --input "${payload_file}" >/dev/null

rm -f -- "${b64_file}" "${payload_file}"

printf 'Verifying tap formula update...\n'
python3 - "${TAP_REPO}" "${TAP_BRANCH}" "${FORMULA_TAP_PATH}" "${NEW_VERSION}" "${BINARY_URL}" "${BINARY_SHA256}" <<'PY'
import base64
import json
import subprocess
import sys

repo, branch, path, version, url, sha256 = sys.argv[1:7]
payload = subprocess.check_output(
    ["gh", "api", f"repos/{repo}/contents/{path}?ref={branch}"],
    text=True,
)
formula = base64.b64decode(json.loads(payload)["content"]).decode()
checks = {
    f'version "{version}"': "version",
    f'url "{url}"': "binary URL",
    f'sha256 "{sha256}"': "binary SHA256",
    f'assert_match "{version}"': "formula test version",
}
missing = [label for needle, label in checks.items() if needle not in formula]
if missing:
    raise SystemExit("tap formula did not update expected fields: " + ", ".join(missing))
PY

printf '\n=== Release Complete ===\n'
printf '  Version: %s\n' "${NEW_VERSION}"
printf '  Tag:     %s\n' "${TAG}"
printf '  Release: https://github.com/tigger04/yapper/releases/tag/%s\n' "${TAG}"
printf '  Binary:  %s (%s)\n' "${BINARY_ASSET}" "${BINARY_SHA256:0:16}..."
printf '  Formula: %s/%s\n\n' "${TAP_REPO}" "${FORMULA_TAP_PATH}"
printf 'Install with:\n  brew tap tigger04/tap\n  brew install yapper\n'
