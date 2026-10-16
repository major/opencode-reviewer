# opencode-reviewer 🔍

A Fedora 44 container with OpenCode V2, GitHub CLI (`gh`), GitLab CLI (`glab`), and a Jira MCP server for code review work. 🐧

## What is inside 📦

| Item | Details |
| --- | --- |
| Base image | Fedora 44 |
| OpenCode | V2, pinned to `2.0.31` by default |
| GitHub CLI | Pinned by `GH_VERSION`, official `cli/cli` release, SHA256 checked before extraction |
| GitLab CLI | Pinned by `GLAB_VERSION`, official `gitlab-org/cli` release, SHA256 checked before extraction |
| Jira MCP | `mcp-atlassian` pinned by `MCP_ATLASSIAN_VERSION`, own virtual environment at `/opt/mcp-atlassian`, read-only by default |
| oh-my-opencode-slim | OpenCode plugin pinned by `OH_MY_OPENCODE_SLIM_VERSION`, installed at build time |
| Python | 3.11 virtual environment, first on `PATH` |
| User | Non-root `opencode` user |

To test other versions, override a build argument: `OPENCODE_VERSION`, `GH_VERSION`, `GLAB_VERSION`, `MCP_ATLASSIAN_VERSION`, or `OH_MY_OPENCODE_SLIM_VERSION`.

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
| mcp-atlassian | PyPI `mcp-atlassian` | Python package pinned for the Jira MCP server |
| oh-my-opencode-slim | npm `oh-my-opencode-slim` | OpenCode plugin installed at build time |

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
  --env JIRA_URL \
  --env JIRA_USERNAME \
  --env JIRA_API_TOKEN \
  -v "$PWD:/workspace:Z" \
  opencode-reviewer
```

`--env NAME` copies the value from your shell, so export the variables first.

## Connect Jira 🎫

The image includes the Jira MCP server, but it does not turn it on. Add it to your own OpenCode config. Use the `mcp-atlassian-jira` wrapper, which applies the safe defaults below:

```json
{
  "mcp": {
    "servers": {
      "jira": { "type": "local", "command": ["mcp-atlassian-jira"] }
    }
  }
}
```

Local MCP servers inherit the container environment. Set the variables that match your Jira type:

| Jira type | Variables |
| --- | --- |
| Jira Cloud | `JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN` |
| Jira Server or Data Center | `JIRA_URL`, `JIRA_PERSONAL_TOKEN` |

Jira Cloud example:

```sh
podman run -it --rm \
  --env JIRA_URL \
  --env JIRA_USERNAME \
  --env JIRA_API_TOKEN \
  -v "$PWD:/workspace:Z" \
  opencode-reviewer
```

Optional settings:

| Variable | Default | What it does |
| --- | --- | --- |
| `READ_ONLY_MODE` | `true` | Blocks changes to Jira. Set `false` to allow comments, transitions, and edits. |
| `TOOLSETS` | `default` | Jira tool groups to enable. Use `all` for everything, or a list such as `default,jira_agile`. |
| `JIRA_PROJECTS_FILTER` | unset | Comma-separated project keys, such as `OPS,PLAT`, to limit results. |

> 💡 **Without `JIRA_URL`:** The Jira MCP server starts with no tools. The rest of OpenCode still works.

## Configure oh-my-opencode-slim 🧩

The plugin is installed with its defaults. To choose your own models or presets, mount your config file read-only:

```sh
podman run -it --rm \
  -v "$HOME/.config/opencode/oh-my-opencode-slim.json:/home/opencode/.config/opencode/oh-my-opencode-slim.json:ro,Z" \
  -v "$PWD:/workspace:Z" \
  opencode-reviewer
```

> 💡 **Mounting your own `opencode.json`?** It replaces the image's config, which holds the plugin entry. Keep `"plugins": ["oh-my-opencode-slim@3.0.4"]` in your config. The package is already cached in the image, so it loads without a download.

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
