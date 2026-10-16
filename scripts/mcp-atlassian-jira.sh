#!/bin/sh
# Starts mcp-atlassian over stdio for OpenCode with reviewer-safe defaults.
# Runtime env vars (for example READ_ONLY_MODE or TOOLSETS) override these defaults.
set -eu

# Read-only by default so the reviewer cannot change Jira issues.
export READ_ONLY_MODE="${READ_ONLY_MODE:-true}"
# Core Jira toolsets only, to keep the tool list small and save context.
export TOOLSETS="${TOOLSETS:-default}"

exec /opt/mcp-atlassian/bin/mcp-atlassian "$@"
