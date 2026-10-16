# opencode-reviewer 🔍

A Fedora 44 container with OpenCode V2, GitHub CLI (`gh`), and GitLab CLI (`glab`) for code review work. 🐧

## What is inside 📦

| Item | Details |
| --- | --- |
| Base image | Fedora 44 |
| OpenCode | V2, pinned to `2.0.31` by default |
| GitHub CLI | Pinned by `GH_VERSION`, official `cli/cli` release, SHA256 checked before extraction |
| GitLab CLI | Pinned by `GLAB_VERSION`, official `gitlab-org/cli` release, SHA256 checked before extraction |
| Python | 3.11 virtual environment, first on `PATH` |
| User | Non-root `opencode` user |

To test other versions, override a build argument: `OPENCODE_VERSION`, `GH_VERSION`, or `GLAB_VERSION`.

```sh
podman build --build-arg OPENCODE_VERSION=2.0.31 --no-cache -f Containerfile -t opencode-reviewer .
```

## Build locally 🛠️

```sh
podman build --no-cache -f Containerfile -t opencode-reviewer .
```

## Keep versions current 🔄

Renovate opens update pull requests for the pinned versions in `Containerfile`. The config in `renovate.json` extends the shared preset `github>major/renovate-config`, which sets the schedule, cooldown, and other update policy.

| Tool | Renovate source | Notes |
| --- | --- | --- |
| OpenCode | npm `@opencode/cli` | Limited to the V2 line |
| GitHub CLI | GitHub releases `cli/cli` | Strips the `v` prefix from tags |
| GitLab CLI | GitLab releases `gitlab-org/cli` | Strips the `v` prefix from tags |

Each tracked version uses a marker comment above its `ARG` line, such as `# renovate: datasource=... depName=...`. Keep the marker directly above the `ARG` line when you edit the Containerfile.

To enable updates, install the Renovate GitHub App on this repository or enable Renovate for it.

## Run the smoke test ✅

Test checksum rejection without network access (requires `jq` and SHA-256 tools):

```sh
sh tests/checksums.sh
```

Mount the tests read-only:

```sh
podman run --rm -v "$PWD/tests:/tests:ro,Z" opencode-reviewer sh /tests/smoke.sh
```

## Start OpenCode in your project 🚀

Mount your project at `/workspace`:

```sh
podman run -it --rm -v "$PWD:/workspace:Z" opencode-reviewer
```

Docker works too:

```sh
docker run -it --rm -v "$PWD:/workspace:Z" opencode-reviewer
```

> 💡 **Permissions:** The container runs as a non-root user. If it cannot write to your project files, use Podman's user namespace mapping:
>
> ```sh
> podman run -it --rm --userns=keep-id -v "$PWD:/workspace:Z" opencode-reviewer
> ```

## Pass credentials at runtime 🔑

Never bake tokens into the image. Pass them when you start the container:

```sh
podman run -it --rm \
  --env GH_TOKEN \
  --env GITLAB_TOKEN \
  -v "$PWD:/workspace:Z" \
  opencode-reviewer
```

`--env NAME` copies the value from your shell, so export the variables first.

## Published image 📤

The GitHub Actions workflow in `.github/workflows/container.yml` builds the image, runs the smoke test, and publishes only after the test passes.

| Event | Published tags |
| --- | --- |
| Push to `main`, scheduled Monday build, or manual run on `main` | `latest`, `sha-<full commit SHA>` |
| Push of a `v*` tag | `<tag name>`, `sha-<full commit SHA>` (never `latest`) |
| Pull requests and manual runs on other branches | None (build and test only) |

The image name is `ghcr.io/OWNER/REPO` in lowercase.

### First publish setup 🧭

1. The workflow logs in with the built-in `GITHUB_TOKEN`. No personal access token is needed.
2. The workflow needs `packages: write`, which it already requests.
3. New packages start as private. To make the image public, open the package settings in GitHub and change the visibility.
4. If the package already exists, open its package settings, then **Manage Actions access**, and make sure this repository has write access.

### Pull the image

```sh
podman pull ghcr.io/OWNER/REPO:latest
```

Replace `OWNER/REPO` with your GitHub owner and repository name in lowercase.
