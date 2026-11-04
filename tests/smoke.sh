#!/bin/sh
set -eu

. /etc/os-release
[ "$VERSION_ID" = "44" ]

[ "$(id -u)" -ne 0 ]

python -c 'import sys; assert sys.version_info[:2] == (3, 11), sys.version; assert sys.prefix != sys.base_prefix, sys.prefix'
python_pip_version=$(python -m pip --version)
pip_version=$(pip --version)
[ "$python_pip_version" = "$pip_version" ]

python -c 'import re, subprocess; version = subprocess.check_output(["opencode", "--version"], text=True).strip(); assert re.search(r"(?:^|\s)v?2\.\d+(?:\.\d+)?(?:\s|$)", version), version'
gh --version
glab --version
git --version
jq --version
rg --version

command -v mcp-atlassian-jira
mcp-atlassian-jira --version
jq -e '.plugins | any(startswith("oh-my-opencode-slim@"))' "$HOME/.config/opencode/opencode.json"

# mcp_tools prints the tool names a stdio MCP server lists after a handshake.
# The server needs no credentials to list tools. The sleep keeps stdin open
# long enough for the reply, then closing stdin stops the server.
mcp_tools() {
    {
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
        printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
        printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
        sleep 3
    } | timeout 30 "$@" 2>/dev/null | jq -r 'select(.id == 2) | .result.tools[].name'
}

command -v gitlab-mcp
gitlab_tools=$(mcp_tools gitlab-mcp)
printf '%s\n' "$gitlab_tools" | grep -qx get_merge_request
printf '%s\n' "$gitlab_tools" | grep -qx post_review_notes

command -v jira-mcp
jira_tools=$(mcp_tools jira-mcp)
printf '%s\n' "$jira_tools" | grep -qx get_issue
printf '%s\n' "$jira_tools" | grep -qx search_issues
