# opencode-reviewer 🔍

A Fedora 44 container with OpenCode V2, GitHub CLI (`gh`), GitLab CLI (`glab`), and the GitLab and Jira MCP servers for code review work. 🐧

## What is inside 📦

| Item | Details |
| --- | --- |
| Base image | Fedora 44 |
| OpenCode | V2, pinned by `OPENCODE_VERSION` |
| GitHub CLI | Pinned by `GH_VERSION`, official `cli/cli` release, SHA256 checked before extraction |
| GitLab CLI | Pinned by `GLAB_VERSION`, official `gitlab-org/cli` release, SHA256 checked before extraction |
| GitLab MCP | [`gitlab-mcp`](https://github.com/major/gitlab-mcp) pinned to a commit by `GITLAB_MCP_REF`, own tool venv under `/opt/mcp-tools`, command `gitlab-mcp` |
| Jira MCP | [`jira-mcp`](https://github.com/major/jira-mcp) pinned to a commit by `JIRA_MCP_REF`, own tool venv under `/opt/mcp-tools`, command `jira-mcp` |
| MCP Python | Managed Python 3.15 from `uv` under `/opt/uv-python`. `uv` itself is not in the image. |
| Python | 3.11 virtual environment, first on `PATH` |
| User | Non-root `opencode` user |

To test other versions, override a build argument: `OPENCODE_VERSION`, `GH_VERSION`, `GLAB_VERSION`, `UV_VERSION`, `GITLAB_MCP_REF`, or `JIRA_MCP_REF`.

```sh
podman build --build-arg OPENCODE_VERSION=2.1.4 --no-cache -f Containerfile -t opencode-reviewer .
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
| uv | PyPI `uv` | Installs the MCP servers at build time, then is removed |
| gitlab-mcp | Git commits on `main` of `major/gitlab-mcp` | Pinned to a commit SHA, bumped by digest |
| jira-mcp | Git commits on `main` of `major/jira-mcp` | Pinned to a commit SHA, bumped by digest |

Each tracked pin uses a marker comment above its `ARG` line, such as `# renovate: datasource=... depName=...`. The MCP commit pins add `packageName=` and `branch=`. Keep the marker directly above the `ARG` line when you edit the Containerfile.

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
  --env GITLAB_URL \
  --env JIRA_URL \
  --env JIRA_EMAIL \
  --env JIRA_API_TOKEN \
  -v "$PWD:/workspace:Z" \
  opencode-reviewer
```

`--env NAME` copies the value from your shell, so export the variables first.

## Connect GitLab and Jira 🦊🎫

The image includes both MCP servers, but it does not turn them on. Add them to your own OpenCode `opencode.json`. Each server is a plain command on `PATH`:

```json
{
  "mcp": {
    "servers": {
      "gitlab": {
        "type": "local",
        "command": ["gitlab-mcp"],
        "environment": {
          "GITLAB_TOKEN": "{env:GITLAB_TOKEN}",
          "GITLAB_URL": "{env:GITLAB_URL}"
        }
      },
      "jira": {
        "type": "local",
        "command": ["jira-mcp"],
        "environment": {
          "JIRA_URL": "{env:JIRA_URL}",
          "JIRA_EMAIL": "{env:JIRA_EMAIL}",
          "JIRA_API_TOKEN": "{env:JIRA_API_TOKEN}"
        }
      }
    }
  }
}
```

| Server | Variables | Notes |
| --- | --- | --- |
| `gitlab-mcp` | `GITLAB_TOKEN`, `GITLAB_URL` | `GITLAB_URL` defaults to `https://gitlab.com`. Set it for a self-managed GitLab. |
| `jira-mcp` | `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` | Jira Cloud only. A scoped token needs the `https://api.atlassian.com/ex/jira/<cloud-id>` URL. |

Both servers list their tools without credentials. A tool call explains which variable is missing.

> ⚠️ **Neither server has a read-only switch.** `jira-mcp` still has comment, transition, assign, and link tools. `gitlab-mcp` has write tools too. For a read-only reviewer, use a read-only token and deny the write tools with OpenCode permissions. OpenCode names each MCP permission `<server>_<tool>`, such as `jira_add_issue_comment`. Rules are checked in order and the last match wins, so put a broad deny first and the allowed tools after it:
>
> ```json
> "permissions": [
>   { "action": "jira_*", "resource": "*", "effect": "deny" },
>   { "action": "jira_get_issue", "resource": "*", "effect": "allow" },
>   { "action": "jira_search_issues", "resource": "*", "effect": "allow" }
> ]
> ```

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
