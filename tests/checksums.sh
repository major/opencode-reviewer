#!/bin/sh
# Tests for checksum verification in scripts/install-clis.sh.
#
# Each scenario runs the real installer with stub curl, uname, tar, and install
# first on PATH. Real jq, awk, and sha256sum do the checks under test.
# Nothing touches the network or /usr/local/bin. All files live in a temp dir.
#
# Usage: sh tests/checksums.sh
set -eu

unset CDPATH
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
installer=$script_dir/../scripts/install-clis.sh

GH_ARCHIVE=gh_2.60.0_linux_amd64.tar.gz
GH_CHECKSUMS=gh_2.60.0_checksums.txt
GLAB_ARCHIVE=glab_1.46.0_linux_amd64.tar.gz
GLAB_CHECKSUMS=checksums.txt

output=/dev/null
work=$(mktemp -d "${TMPDIR:-/tmp}/checksums-test.XXXXXX")
trap 'rm -rf "$work"' 0
trap 'exit 1' HUP INT TERM

# fail LABEL MESSAGE: prints a labelled failure with installer output, then exits.
fail() {
    printf '❌ FAIL [%s]: %s\n' "$1" "$2" >&2
    if [ -s "$output" ]; then
        printf -- '--- installer output ---\n' >&2
        cat "$output" >&2
    fi
    exit 1
}

# make_stubs: writes fake curl, uname, tar, and install into $work/bin.
# The curl stub serves only known URLs from $FAKE_SERVER and never uses the network.
# The tar and install stubs log their calls to $FAKE_EVENTS and change nothing.
make_stubs() {
    mkdir -p "$work/bin"
    cat > "$work/bin/curl" <<'EOF'
#!/bin/sh
set -eu
out= url=
fail() { printf 'fake curl: %s\n' "$*" >&2; exit 2; }
while [ "$#" -gt 0 ]; do
    case $1 in
        -o) [ "$#" -ge 2 ] || fail "-o needs a path"; out=$2; shift 2 ;;
        --retry) [ "$#" -ge 2 ] || fail "--retry needs a count"; shift 2 ;;
        -fsSL | --retry-all-errors) shift ;;
        https://*) url=$1; shift ;;
        *) fail "unexpected argument: $1" ;;
    esac
done
[ -n "$out" ] || fail "missing -o"
printf 'curl %s\n' "$url" >> "$FAKE_EVENTS"
case $url in
    https://api.github.com/repos/cli/cli/releases/tags/v2.60.0) src=gh-release.json ;;
    https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/v1.46.0) src=glab-release.json ;;
    https://github.com/cli/cli/releases/download/v2.60.0/gh_2.60.0_checksums.txt) src=gh_2.60.0_checksums.txt ;;
    https://github.com/cli/cli/releases/download/v2.60.0/gh_2.60.0_linux_amd64.tar.gz) src=gh_2.60.0_linux_amd64.tar.gz ;;
    https://gitlab.com/gitlab-org/cli/-/releases/v1.46.0/downloads/glab_1.46.0_linux_amd64.tar.gz) src=glab_1.46.0_linux_amd64.tar.gz ;;
    https://gitlab.com/gitlab-org/cli/-/releases/v1.46.0/downloads/checksums.txt) src=checksums.txt ;;
    *) fail "unknown URL: $url" ;;
esac
if [ ! -f "$FAKE_SERVER/$src" ]; then
    printf 'curl: (22) The requested URL returned error: 404\n' >&2
    exit 22
fi
cat "$FAKE_SERVER/$src" > "$out"
EOF
    cat > "$work/bin/uname" <<'EOF'
#!/bin/sh
printf 'x86_64\n'
EOF
    cat > "$work/bin/tar" <<'EOF'
#!/bin/sh
printf 'tar %s\n' "$*" >> "$FAKE_EVENTS"
EOF
    cat > "$work/bin/install" <<'EOF'
#!/bin/sh
printf 'install %s\n' "$*" >> "$FAKE_EVENTS"
EOF
    chmod +x "$work"/bin/*
}

# record FILE NAME: prints a sha256sum-style record with the real hash of FILE under NAME.
record() {
    record_hash=$(sha256sum "$1")
    printf '%s  %s\n' "${record_hash%% *}" "$2"
}

# make_server DIR: writes valid release JSON, fake archive payloads, and true checksum files.
make_server() {
    mkdir -p "$1"
    cat > "$1/gh-release.json" <<'EOF'
{
  "url": "https://api.github.com/repos/cli/cli/releases/1",
  "tag_name": "v2.60.0",
  "name": "v2.60.0",
  "draft": false,
  "prerelease": false,
  "assets": [
    {
      "name": "gh_2.60.0_checksums.txt",
      "content_type": "text/plain",
      "browser_download_url": "https://github.com/cli/cli/releases/download/v2.60.0/gh_2.60.0_checksums.txt"
    },
    {
      "name": "gh_2.60.0_linux_amd64.tar.gz",
      "content_type": "application/gzip",
      "browser_download_url": "https://github.com/cli/cli/releases/download/v2.60.0/gh_2.60.0_linux_amd64.tar.gz"
    }
  ]
}
EOF
    cat > "$1/glab-release.json" <<'EOF'
{
  "tag_name": "v1.46.0",
  "name": "v1.46.0",
  "released_at": "2024-06-01T00:00:00.000Z",
  "assets": {
    "count": 2,
    "links": [
      {
        "id": 2,
        "name": "glab_1.46.0_linux_amd64.tar.gz",
        "url": "https://gitlab.com/gitlab-org/cli/-/releases/v1.46.0/downloads/glab_1.46.0_linux_amd64.tar.gz",
        "direct_asset_url": "https://gitlab.com/gitlab-org/cli/-/releases/v1.46.0/downloads/glab_1.46.0_linux_amd64.tar.gz",
        "link_type": "other"
      },
      {
        "id": 3,
        "name": "checksums.txt",
        "url": "https://gitlab.com/gitlab-org/cli/-/releases/v1.46.0/downloads/checksums.txt",
        "direct_asset_url": "https://gitlab.com/gitlab-org/cli/-/releases/v1.46.0/downloads/checksums.txt",
        "link_type": "other"
      }
    ]
  }
}
EOF
    printf 'fake gh archive\n' > "$1/$GH_ARCHIVE"
    printf 'fake glab archive\n' > "$1/$GLAB_ARCHIVE"
    record "$1/$GH_ARCHIVE" "$GH_ARCHIVE" > "$1/$GH_CHECKSUMS"
    record "$1/$GLAB_ARCHIVE" "$GLAB_ARCHIVE" > "$1/$GLAB_CHECKSUMS"
}

# inject TOOL FAULT SERVER_DIR: breaks TOOL's fixtures in SERVER_DIR as FAULT describes.
# Faults: checksum faults, download-error, or tag-mismatch.
inject() {
    case $1 in
        gh) archive=$GH_ARCHIVE checksums=$GH_CHECKSUMS ;;
        glab) archive=$GLAB_ARCHIVE checksums=$GLAB_CHECKSUMS ;;
    esac
    case $2 in
        wrong-checksum)
            printf '%064d  %s\n' 0 "$archive" > "$3/$checksums" ;;
        missing-name)
            # The only record names a different file, so the archive has no record.
            record "$3/$archive" "other-$archive" > "$3/$checksums" ;;
        duplicate-record)
            # Two identical records for the archive must be rejected as ambiguous.
            line=$(record "$3/$archive" "$archive")
            printf '%s\n%s\n' "$line" "$line" > "$3/$checksums" ;;
        download-error)
            # The stub curl answers 404 for a missing file, like curl -f does.
            rm -f "$3/$archive" ;;
        tag-mismatch)
            case $1 in
                gh) metadata=$3/gh-release.json; mismatched_tag=v2.60.1 ;;
                glab) metadata=$3/glab-release.json; mismatched_tag=v1.46.1 ;;
            esac
            jq --arg tag "$mismatched_tag" '.tag_name = $tag' "$metadata" > "$metadata.tmp"
            mv "$metadata.tmp" "$metadata" ;;
    esac
}

# run_installer CASE_DIR VERSION_CASE: runs the installer with pinned fixtures and optional bad versions.
run_installer() {
    case_dir=$1
    version_case=${2:-valid}
    output=$case_dir/output.log
    mkdir -p "$case_dir/tmp"
    : > "$case_dir/events.log"
    STATUS=0
    (
        PATH="$work/bin:$PATH"
        TMPDIR=$case_dir/tmp
        FAKE_SERVER=$case_dir/server
        FAKE_EVENTS=$case_dir/events.log
        GH_VERSION=2.60.0
        GLAB_VERSION=1.46.0
        export PATH TMPDIR FAKE_SERVER FAKE_EVENTS GH_VERSION GLAB_VERSION
        case $version_case in
            valid) ;;
            missing-gh) unset GH_VERSION ;;
            missing-glab) unset GLAB_VERSION ;;
            invalid-gh) GH_VERSION=2.60.0/path ;;
            invalid-glab) GLAB_VERSION=v1.46.0 ;;
            *) printf 'unknown version test case: %s\n' "$version_case" >&2; exit 2 ;;
        esac
        sh "$installer"
    ) > "$output" 2>&1 || STATUS=$?
}

# count_events PREFIX: counts logged stub calls for PREFIX ("tar" or "install") in the case.
count_events() {
    grep -c "^$1 " "$case_dir/events.log" || :
}

# scenario LABEL TOOL FAULT: builds fixtures, injects FAULT into TOOL, and checks the outcome.
# A FAULT of "none" must install both tools. Any other FAULT must fail before extraction.
scenario() {
    label=$1
    case_dir=$work/cases/$2-$3
    make_server "$case_dir/server"
    if [ "$3" != none ]; then
        inject "$2" "$3" "$case_dir/server"
    fi
    run_installer "$case_dir"

    tars=$(count_events tar)
    installs=$(count_events install)
    if [ "$3" = none ]; then
        [ "$STATUS" -eq 0 ] || fail "$label" "installer exited $STATUS"
        [ "$tars" -eq 2 ] && [ "$installs" -eq 2 ] \
            || fail "$label" "expected 2 tar and 2 install calls, got $tars and $installs"
    else
        [ "$STATUS" -ne 0 ] || fail "$label" "installer exited 0 for a bad download"
        [ "$tars" -eq 0 ] && [ "$installs" -eq 0 ] \
            || fail "$label" "extract or install ran before verification: $tars tar, $installs install"
    fi
    if [ "$3" = tag-mismatch ]; then
        case $2 in
            gh) rejected_assets=https://github.com/cli/cli/releases/download/v2.60.0/ ;;
            glab) rejected_assets=https://gitlab.com/gitlab-org/cli/-/releases/v1.46.0/downloads/ ;;
        esac
        if grep -Fq "$rejected_assets" "$case_dir/events.log"; then
            fail "$label" "assets were downloaded despite the mismatched release tag"
        fi
    fi
    [ -z "$(ls -A "$case_dir/tmp")" ] || fail "$label" "installer left temp files behind"
    printf '✅ ok [%s]\n' "$label"
}

# version_validation MODE: requires missing or malformed version inputs to fail before curl, tar, or install.
version_validation() {
    label=$1
    mode=$2
    case_dir=$work/cases/version-$mode
    make_server "$case_dir/server"
    run_installer "$case_dir" "$mode"
    [ "$STATUS" -ne 0 ] || fail "$label" "installer accepted a missing or malformed version"
    curls=$(count_events curl)
    tars=$(count_events tar)
    installs=$(count_events install)
    [ "$curls" -eq 0 ] && [ "$tars" -eq 0 ] && [ "$installs" -eq 0 ] \
        || fail "$label" "work began before version validation: $curls curl, $tars tar, $installs install"
    [ -z "$(ls -A "$case_dir/tmp")" ] || fail "$label" "installer left temp files behind"
    printf '✅ ok [%s]\n' "$label"
}

for tool in jq awk sha256sum; do
    command -v "$tool" > /dev/null || fail setup "missing required tool: $tool"
done
[ -f "$installer" ] || fail setup "installer not found: $installer"

make_stubs
scenario "valid fixtures" none none
for tool in gh glab; do
    scenario "$tool wrong checksum" "$tool" wrong-checksum
    scenario "$tool missing checksum filename" "$tool" missing-name
    scenario "$tool duplicate checksum record" "$tool" duplicate-record
    scenario "$tool download error" "$tool" download-error
done
version_validation "missing GH_VERSION" missing-gh
version_validation "missing GLAB_VERSION" missing-glab
version_validation "invalid GH_VERSION" invalid-gh
version_validation "invalid GLAB_VERSION" invalid-glab
scenario "gh mismatched metadata tag" gh tag-mismatch
scenario "glab mismatched metadata tag" glab tag-mismatch

printf '🎉 all checksum scenarios passed\n'
