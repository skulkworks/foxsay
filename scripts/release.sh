#!/bin/bash
# FoxSay release wrapper — thin shim over Den's shared pipeline, plus FoxSay's own
# publish step (Sparkle updates are hosted on Cloudflare R2 at updates.skulkworks.dev,
# the same bucket the other SkulkWorks apps use).
#
# Usage:
#   scripts/release.sh keys              # generate-sparkle-keys.sh (once, ever)
#   scripts/release.sh build [args]      # archive → notarize → DMG (build/FoxSay.dmg)
#   scripts/release.sh changelog         # compile changelog/*.md → docs/changelog.json
#   scripts/release.sh appcast [ver]     # sign DMG → docs/appcast.xml (R2 URLs)
#   scripts/release.sh publish [ver]     # upload versioned DMG + appcast + changelog to R2
#   scripts/release.sh cask [ver]        # bump + push the Homebrew cask to this build
#   scripts/release.sh verify [ver]      # re-check the live DMG and the Homebrew cask
#   scripts/release.sh pages             # commit + push docs/ so GitHub Pages serves it too
#   scripts/release.sh github [ver]      # tag + GitHub Release with the DMG attached
#   scripts/release.sh release [args]    # build → changelog → appcast → publish → pages → github
#
# Notarization needs APPLE_ID and APPLE_APP_PASSWORD in the environment.
# Publishing needs the `skulkworks-updates` profile in ~/.aws/credentials.
# The GitHub Release needs the `gh` CLI, authenticated.
#
# TWO FEED LOCATIONS, ON PURPOSE. 2.0.0 and later poll R2 at
# https://updates.skulkworks.dev/foxsay/appcast.xml, matching the other apps.
# Every copy up to and including 1.0.9 has https://skulkworks.github.io/foxsay/appcast.xml
# baked in and cannot be changed retroactively, so GitHub Pages keeps serving the
# same feed from docs/. Both locations get the identical appcast and changelog;
# only the host differs, and both point at the same R2 DMG. A 1.0.9 user polls
# Pages, sees the release, downloads from R2, and polls R2 from then on.
#
# GITHUB RELEASES ARE A THIRD LOCATION, and not a feed — nothing polls them. FoxSay
# is a public repo, its README download badge reads the latest GitHub release, and
# that is where anyone who finds the project on GitHub goes to download it. 1.0.0
# through 1.0.9 were published there because GitHub Releases also hosted the DMG;
# moving hosting to R2 at 2.0.0 dropped the step along with it, and GitHub sat on
# 1.0.9 while the site served 2.1.0. Every release now gets a tag, a GitHub Release
# and a copy of the same DMG, on top of the R2 upload.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Den lives beside the FoxSay repo (../den). Override with DEN_DIR if it moved.
# FoxSay is a public repo and Den is private, so this is a maintainer-only path:
# the app itself builds from a clean clone with no Den checkout (the apps and
# changelog feed code is vendored into FoxSayPackage for exactly that reason).
DEN_DIR="${DEN_DIR:-$PROJECT_ROOT/../den}"
if [ ! -d "$DEN_DIR/scripts" ]; then
    echo "[ERROR] Den scripts not found at $DEN_DIR/scripts (set DEN_DIR)" >&2
    echo "        Releasing FoxSay needs the private skulkworks/den checkout." >&2
    exit 1
fi

# FoxSay's parameters, exported for the Den scripts.
export APP_NAME="FoxSay"
export SCHEME="FoxSay"
export WORKSPACE="FoxSay.xcworkspace"
export BUNDLE_ID="com.skulkworks.FoxSay"
export TEAM_ID="M5N5FDK55S"
export GITHUB_REPO="skulkworks/foxsay"
export PROJECT_ROOT

# mlx-swift ships a build plugin (CudaBuild) and mlx-swift-lm a macro
# (#hubDownloader), both untrusted until opened in Xcode — an archive without
# these fails validation. No other SkulkWorks app pulls in SPM plugins, so Den's
# shared build script takes them from here rather than hardcoding them.
export XCODEBUILD_FLAGS="-skipPackagePluginValidation -skipMacroValidation"

# --- Update hosting (Cloudflare R2, custom domain updates.skulkworks.dev) ----------
# The app's Sparkle feed URL (FoxSay/Info.plist) is baked to
# https://updates.skulkworks.dev/foxsay/appcast.xml — these must stay in sync.
# One shared bucket serves every SkulkWorks app, namespaced by prefix.
UPDATES_HOST="${UPDATES_HOST:-updates.skulkworks.dev}"
UPDATES_PREFIX="${UPDATES_PREFIX:-foxsay}"
R2_BUCKET="${R2_BUCKET:-skulkworks-updates}"
R2_PROFILE="${R2_PROFILE:-skulkworks-updates}"
R2_ENDPOINT="${R2_ENDPOINT:-https://e02834c53ddf0e7d19d3387d5a2970e7.r2.cloudflarestorage.com}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"

# Resolve marketing version / build number from the built app (same source Den uses).
resolve_version() {
    local v="$1"
    if [ -z "$v" ] && [ -d "$BUILD_DIR/$APP_NAME.app" ]; then
        v=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
            "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || echo "")
    fi
    if [ -z "$v" ]; then
        echo "[ERROR] Could not determine version. Build first, or pass it explicitly." >&2
        exit 1
    fi
    echo "$v"
}
resolve_build() {
    local b=""
    if [ -d "$BUILD_DIR/$APP_NAME.app" ]; then
        b=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" \
            "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || echo "")
    fi
    [ -n "$b" ] || { echo "[ERROR] Could not determine build number. Build first." >&2; exit 1; }
    echo "$b"
}

# The published DMG name carries BOTH marketing version and build number, e.g.
# FoxSay-2.0.0-11.dmg. This makes every build a unique, immutable URL — the Cloudflare
# edge can never serve stale bytes for a reused name (which breaks Sparkle's signature
# check), and immutable artifacts can be cached forever.
dmg_name() { echo "$APP_NAME-$(resolve_version "$1")-$(resolve_build).dmg"; }

do_appcast() {
    local version; version=$(resolve_version "$1")
    # Point the appcast at R2: the enclosure is the build-stamped DMG, the feed lives at
    # https://$UPDATES_HOST/$UPDATES_PREFIX/appcast.xml.
    export PAGES_HOST="$UPDATES_HOST"
    export DOWNLOAD_URL="https://$UPDATES_HOST/$UPDATES_PREFIX/$(dmg_name "$version")"
    "$DEN_DIR/scripts/generate-appcast.sh" "$version"
}

do_cask() {
    local version; version=$(resolve_version "$1")
    "$DEN_DIR/scripts/update-cask.sh" "$version" "$(resolve_build)"
}

do_verify() {
    local version; version=$(resolve_version "$1")
    "$DEN_DIR/scripts/verify-publish.sh" "$version" "$(resolve_build)"
}

do_publish() {
    local version; version=$(resolve_version "$1")
    local name; name=$(dmg_name "$version")
    local dmg="$BUILD_DIR/$APP_NAME.dmg"
    local appcast="$PROJECT_ROOT/docs/appcast.xml"
    local changelog="$PROJECT_ROOT/docs/changelog.json"
    [ -f "$dmg" ]       || { echo "[ERROR] DMG not found at $dmg (run build)" >&2; exit 1; }
    [ -f "$appcast" ]   || { echo "[ERROR] appcast not found at $appcast (run appcast)" >&2; exit 1; }
    [ -f "$changelog" ] || { echo "[ERROR] changelog not found at $changelog (run changelog)" >&2; exit 1; }

    # Never publish an unnotarized build: Den's build step silently skips
    # notarization when APPLE_ID / APPLE_APP_PASSWORD are unset, and Gatekeeper
    # rejects the result on other Macs. The staple check catches that here, at
    # the last gate before the DMG goes live. FOXSAY_PUBLISH_UNNOTARIZED=1
    # overrides for a deliberate local-only test publish.
    if [ "${FOXSAY_PUBLISH_UNNOTARIZED:-0}" != "1" ]; then
        if ! xcrun stapler validate "$dmg" >/dev/null 2>&1; then
            echo "[ERROR] $dmg has no notarization ticket stapled - refusing to publish." >&2
            echo "        Set APPLE_ID / APPLE_APP_PASSWORD and re-run the build, or" >&2
            echo "        FOXSAY_PUBLISH_UNNOTARIZED=1 to override deliberately." >&2
            exit 1
        fi
    fi

    echo "[INFO] Uploading $name to R2 ($R2_BUCKET/$UPDATES_PREFIX)..."
    aws s3 cp "$dmg" "s3://$R2_BUCKET/$UPDATES_PREFIX/$name" \
        --profile "$R2_PROFILE" --endpoint-url "$R2_ENDPOINT" \
        --content-type "application/x-apple-diskimage" \
        --cache-control "public, max-age=31536000, immutable"

    # Changelog feed for the website and the in-app What's New window. No-cache like
    # the appcast, so a new release's notes show up immediately.
    echo "[INFO] Uploading changelog.json to R2..."
    aws s3 cp "$changelog" "s3://$R2_BUCKET/$UPDATES_PREFIX/changelog.json" \
        --profile "$R2_PROFILE" --endpoint-url "$R2_ENDPOINT" \
        --content-type "application/json" --cache-control "no-cache, max-age=0"

    # Upload the appcast last (and no-cache) so clients never see a new appcast that
    # points at a DMG that hasn't finished uploading, and always re-fetch it.
    echo "[INFO] Uploading appcast.xml to R2..."
    aws s3 cp "$appcast" "s3://$R2_BUCKET/$UPDATES_PREFIX/appcast.xml" \
        --profile "$R2_PROFILE" --endpoint-url "$R2_ENDPOINT" \
        --content-type "application/xml" --cache-control "no-cache, max-age=0"

    # The website caches each appcast lookup (a fetch costs ~600ms because R2 serves
    # these no-cache, and a landing page needs the version three times). Drop that
    # cache now so the new version shows up immediately instead of when the TTL
    # lapses. Non-fatal: the site self-heals within the hour if this can't run.
    echo "[INFO] Purging the website version cache..."
    if ssh -o ConnectTimeout=10 rhuk-personal \
        'rm -f ~/webapps/skulkworks/user/data/skulkworks-versions/*.json && \
         cd ~/webapps/skulkworks && /RunCloud/Packages/php83rc/bin/php bin/grav clearcache' \
        >/dev/null 2>&1; then
        echo "[INFO] Website will pick up the new version on the next request."
    else
        echo "[WARN] Could not reach the website to purge its version cache."
        echo "[WARN] It will catch up on its own within the hour."
    fi

    echo ""
    echo "[INFO] Published to R2. Live URLs:"
    echo "  Appcast:   https://$UPDATES_HOST/$UPDATES_PREFIX/appcast.xml"
    echo "  Changelog: https://$UPDATES_HOST/$UPDATES_PREFIX/changelog.json"
    echo "  DMG:       https://$UPDATES_HOST/$UPDATES_PREFIX/$name"

    # Bump the Homebrew cask to what was just published. It lives in a different
    # repo, so before this ran automatically every release ended green and left
    # `brew install` broken until someone edited the tap by hand.
    "$DEN_DIR/scripts/update-cask.sh" "$version" "$(resolve_build)"

    # Verify what actually landed: that R2 serves the bytes we just uploaded, and that
    # the Homebrew cask matches them. A stale cask sha reads correct on every version
    # number and only fails once someone runs brew install, so it is checked here rather
    # than trusted. Still an independent check: update-cask.sh writes the cask from the
    # local DMG, this re-downloads the live one and proves the two agree. Runs last so
    # the URLs above are printed either way.
    "$DEN_DIR/scripts/verify-publish.sh" "$version" "$(resolve_build)"
}

# The second feed location: docs/ is GitHub Pages' source, so committing and
# pushing it publishes the same appcast and changelog at
# https://skulkworks.github.io/foxsay/. That is the only feed 1.0.9 and earlier
# know about, so skipping this strands every existing install.
do_pages() {
    local appcast="$PROJECT_ROOT/docs/appcast.xml"
    local changelog="$PROJECT_ROOT/docs/changelog.json"
    [ -f "$appcast" ]   || { echo "[ERROR] appcast not found at $appcast (run appcast)" >&2; exit 1; }
    [ -f "$changelog" ] || { echo "[ERROR] changelog not found at $changelog (run changelog)" >&2; exit 1; }

    cd "$PROJECT_ROOT"
    # --porcelain rather than `git diff`, so a first-ever changelog.json (untracked)
    # is not mistaken for "nothing to publish".
    if [ -z "$(git status --porcelain -- docs/appcast.xml docs/changelog.json)" ]; then
        echo "[INFO] docs/ unchanged — GitHub Pages is already serving this release."
        return 0
    fi

    git add docs/appcast.xml docs/changelog.json
    git commit -m "Publish $(resolve_version "") to GitHub Pages"
    git push origin HEAD

    echo "[INFO] Pages updated (may take a minute to go live):"
    echo "  Appcast:   https://skulkworks.github.io/$UPDATES_PREFIX/appcast.xml"
    echo "  Changelog: https://skulkworks.github.io/$UPDATES_PREFIX/changelog.json"
}

# Tag the release and publish it on GitHub with the DMG attached. Idempotent: an
# existing tag is reused rather than moved, and an existing release has its notes and
# asset replaced, so re-running after a failure part-way through is safe.
do_github() {
    local version; version=$(resolve_version "$1")
    local name; name=$(dmg_name "$version")
    local dmg="$BUILD_DIR/$APP_NAME.dmg"
    local notes="$PROJECT_ROOT/changelog/$version.md"

    command -v gh >/dev/null 2>&1 || { echo "[ERROR] gh CLI not found - install it to publish GitHub Releases." >&2; exit 1; }
    [ -f "$dmg" ]   || { echo "[ERROR] DMG not found at $dmg (run build)" >&2; exit 1; }
    [ -f "$notes" ] || { echo "[ERROR] Release notes not found at $notes" >&2; exit 1; }

    cd "$PROJECT_ROOT"

    # The tag is created here rather than by hand, so it always lands on the commit
    # that was actually published (the pages commit, since do_pages runs first).
    if git rev-parse -q --verify "refs/tags/$version" >/dev/null; then
        echo "[INFO] Tag $version already exists locally."
    else
        echo "[INFO] Tagging $version at $(git rev-parse --short HEAD)..."
        git tag -a "$version" -m "$APP_NAME $version"
    fi
    git push origin "refs/tags/$version"

    # Release notes are the changelog entry with its YAML frontmatter stripped —
    # the same text the appcast and the in-app What's New window render.
    local body; body=$(awk '
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---"      { fm = 0; next }
        !fm' "$notes" | sed '/./,$!d')

    # gh names the asset after the file, so publish the DMG under the same
    # build-stamped name R2 and the Homebrew cask use rather than a bare FoxSay.dmg.
    local staged; staged=$(mktemp -d)
    trap 'rm -rf "$staged"' RETURN
    cp "$dmg" "$staged/$name"

    if gh release view "$version" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
        echo "[INFO] Updating the existing $version release..."
        gh release edit "$version" --repo "$GITHUB_REPO" --title "$version" --notes "$body"
        gh release upload "$version" "$staged/$name" --repo "$GITHUB_REPO" --clobber
    else
        echo "[INFO] Creating the $version release..."
        gh release create "$version" "$staged/$name" \
            --repo "$GITHUB_REPO" --title "$version" --notes "$body"
    fi

    echo "[INFO] GitHub Release live:"
    echo "  https://github.com/$GITHUB_REPO/releases/tag/$version"
}

command="${1:-build}"
shift || true

case "$command" in
    build)
        "$DEN_DIR/scripts/build-release.sh" "$@"
        ;;
    changelog)
        "$DEN_DIR/scripts/generate-changelog.sh" "$@"
        ;;
    appcast)
        do_appcast "$@"
        ;;
    publish)
        do_publish "$@"
        ;;
    cask)
        do_cask "$@"
        ;;
    verify)
        do_verify "$@"
        ;;
    pages)
        do_pages
        ;;
    github)
        do_github "$@"
        ;;
    release)
        "$DEN_DIR/scripts/build-release.sh" "$@"
        "$DEN_DIR/scripts/generate-changelog.sh"
        do_appcast ""
        do_publish ""
        do_pages
        do_github ""
        ;;
    keys)
        "$DEN_DIR/scripts/generate-sparkle-keys.sh" "$@"
        ;;
    *)
        echo "[ERROR] Unknown command: $command" >&2
        sed -n '2,20p' "$0" >&2
        exit 1
        ;;
esac
