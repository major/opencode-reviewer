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

command -v mcp-atlassian-jira
mcp-atlassian-jira --version
jq -e '.plugins | any(startswith("oh-my-opencode-slim@"))' "$HOME/.config/opencode/opencode.json"
