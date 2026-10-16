#!/bin/sh
set -eu

GH_VERSION=${GH_VERSION:?GH_VERSION is required}
GLAB_VERSION=${GLAB_VERSION:?GLAB_VERSION is required}

# valid_version accepts only numeric MAJOR.MINOR.PATCH values without path characters.
valid_version() {
    case $1 in
        ''|*[!0-9.]*) return 1 ;;
        *.*.*) ;;
        *) return 1 ;;
    esac

    version_major=${1%%.*}
    version_remainder=${1#*.}
    version_minor=${version_remainder%%.*}
    version_patch=${version_remainder#*.}
    case $version_patch in
        *.*|'') return 1 ;;
    esac
    [ -n "$version_major" ] && [ -n "$version_minor" ] && [ -n "$version_patch" ]
}

if ! valid_version "$GH_VERSION"; then
    printf 'Invalid GH_VERSION: %s (expected MAJOR.MINOR.PATCH)\n' "$GH_VERSION" >&2
    exit 1
fi
if ! valid_version "$GLAB_VERSION"; then
    printf 'Invalid GLAB_VERSION: %s (expected MAJOR.MINOR.PATCH)\n' "$GLAB_VERSION" >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *)
        printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' 0
trap 'exit 1' HUP INT TERM

gh_dir=$tmpdir/gh
glab_dir=$tmpdir/glab
mkdir "$gh_dir" "$glab_dir"

curl -fsSL --retry 3 --retry-all-errors \
    "https://api.github.com/repos/cli/cli/releases/tags/v${GH_VERSION}" \
    -o "$gh_dir/release.json"
jq -er --arg expected "v${GH_VERSION}" '
    .tag_name | if . == $expected then . else error("release tag does not match requested version") end
' "$gh_dir/release.json" > /dev/null
gh_version=$GH_VERSION
gh_archive=gh_${gh_version}_linux_${arch}.tar.gz
gh_checksums=gh_${gh_version}_checksums.txt
gh_archive_url=$(jq -er --arg name "$gh_archive" '
    [.assets[] | select(.name == $name) | .browser_download_url
        | select(type == "string" and length > 0)]
    | if length == 1 then .[0] else error("expected exactly one matching archive URL") end
' "$gh_dir/release.json")
gh_checksums_url=$(jq -er --arg name "$gh_checksums" '
    [.assets[] | select(.name == $name) | .browser_download_url
        | select(type == "string" and length > 0)]
    | if length == 1 then .[0] else error("expected exactly one matching checksum URL") end
' "$gh_dir/release.json")

curl -fsSL --retry 3 --retry-all-errors "$gh_archive_url" -o "$gh_dir/$gh_archive"
curl -fsSL --retry 3 --retry-all-errors "$gh_checksums_url" -o "$gh_dir/$gh_checksums"

curl -fsSL --retry 3 --retry-all-errors \
    "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/v${GLAB_VERSION}" \
    -o "$glab_dir/release.json"
jq -er --arg expected "v${GLAB_VERSION}" '
    .tag_name | if . == $expected then . else error("release tag does not match requested version") end
' "$glab_dir/release.json" > /dev/null
glab_version=$GLAB_VERSION
glab_archive=glab_${glab_version}_linux_${arch}.tar.gz
glab_checksums=checksums.txt
glab_archive_url=$(jq -er --arg name "$glab_archive" '
    [.assets.links[] | select(.name == $name) | (.direct_asset_url // .url)
        | select(type == "string" and length > 0)]
    | if length == 1 then .[0] else error("expected exactly one matching archive URL") end
' "$glab_dir/release.json")
glab_checksums_url=$(jq -er --arg name "$glab_checksums" '
    [.assets.links[] | select(.name == $name) | (.direct_asset_url // .url)
        | select(type == "string" and length > 0)]
    | if length == 1 then .[0] else error("expected exactly one matching checksum URL") end
' "$glab_dir/release.json")

curl -fsSL --retry 3 --retry-all-errors "$glab_archive_url" -o "$glab_dir/$glab_archive"
curl -fsSL --retry 3 --retry-all-errors "$glab_checksums_url" -o "$glab_dir/$glab_checksums"

# Accept only one checksum record whose filename exactly matches the downloaded archive.
awk -v archive="$gh_archive" '
    $2 == archive || $2 == ("*" archive) {
        records++
        if (length($1) == 64 && $1 ~ /^[[:xdigit:]]+$/) {
            hash = $1
        } else {
            invalid = 1
        }
    }
    END {
        if (records != 1 || invalid || hash == "") {
            exit 1
        }
        printf "%s  %s\n", hash, archive
    }
' "$gh_dir/$gh_checksums" > "$gh_dir/verify.sha256"
awk -v archive="$glab_archive" '
    $2 == archive || $2 == ("*" archive) {
        records++
        if (length($1) == 64 && $1 ~ /^[[:xdigit:]]+$/) {
            hash = $1
        } else {
            invalid = 1
        }
    }
    END {
        if (records != 1 || invalid || hash == "") {
            exit 1
        }
        printf "%s  %s\n", hash, archive
    }
' "$glab_dir/$glab_checksums" > "$glab_dir/verify.sha256"

(cd "$gh_dir" && sha256sum -c verify.sha256)
(cd "$glab_dir" && sha256sum -c verify.sha256)

gh_binary_dir=gh_${gh_version}_linux_${arch}
tar -xzf "$gh_dir/$gh_archive" -C "$gh_dir" --no-same-owner -- "$gh_binary_dir/bin/gh"
tar -xzf "$glab_dir/$glab_archive" -C "$glab_dir" --no-same-owner -- bin/glab

install -m 0755 "$gh_dir/$gh_binary_dir/bin/gh" /usr/local/bin/gh
install -m 0755 "$glab_dir/bin/glab" /usr/local/bin/glab
