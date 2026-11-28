FROM registry.fedoraproject.org/fedora:44@sha256:c1e457a3c398b0d7b12d060ad86ad52bab714a17faecc907deb1262fb2b72d98

# renovate: datasource=npm depName=@opencode/cli
ARG OPENCODE_VERSION=2.3.0
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=2.104.0
# renovate: datasource=gitlab-releases depName=gitlab-org/cli
ARG GLAB_VERSION=1.130.0
# renovate: datasource=pypi depName=uv
ARG UV_VERSION=0.13.9
# renovate: datasource=git-refs depName=gitlab-mcp packageName=https://github.com/major/gitlab-mcp branch=main
ARG GITLAB_MCP_REF=6c63c6d9143ea9c1ac1ac9e6d017fd0d091c84da
# renovate: datasource=git-refs depName=jira-mcp packageName=https://github.com/major/jira-mcp branch=main
ARG JIRA_MCP_REF=ab79a352a798e9c685b4ca4be12ae97af0eb81c9

ENV SHELL=/bin/bash \
    PATH=/home/opencode/.venv/bin:/home/opencode/.opencode/bin:${PATH}

RUN dnf -y install \
        ca-certificates \
        curl-minimal \
        tar \
        gzip \
        libstdc++ \
        coreutils \
        gawk \
        git \
        openssh-clients \
        jq \
        ripgrep \
        python3.11 \
        python-pip-wheel \
        python-setuptools-wheel \
        shadow-utils \
    && dnf clean all

COPY scripts/install-clis.sh /usr/local/libexec/install-clis.sh

RUN sh /usr/local/libexec/install-clis.sh

# gitlab-mcp and jira-mcp need Python 3.15, which Fedora 44 lacks, so uv
# fetches a managed Python. Each server gets its own isolated tool venv.
# uv only installs here: the throwaway bootstrap venv is removed afterward,
# and the executables land in /usr/local/bin. Neither server runs until a
# client config starts it. The last two commands start each server on empty
# stdin, which exits 0 once the server imports cleanly.
RUN python3.11 -m venv /opt/uv-bootstrap \
    && /opt/uv-bootstrap/bin/pip install --no-cache-dir "uv==${UV_VERSION}" \
    && export UV_NO_CACHE=1 UV_PYTHON_INSTALL_DIR=/opt/uv-python UV_TOOL_DIR=/opt/mcp-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    && /opt/uv-bootstrap/bin/uv tool install --python 3.15 "gitlab-mcp @ git+https://github.com/major/gitlab-mcp@${GITLAB_MCP_REF}" \
    && /opt/uv-bootstrap/bin/uv tool install --python 3.15 "jira-mcp @ git+https://github.com/major/jira-mcp@${JIRA_MCP_REF}" \
    && rm -rf /opt/uv-bootstrap \
    && gitlab-mcp < /dev/null > /dev/null 2>&1 \
    && jira-mcp < /dev/null > /dev/null 2>&1

RUN useradd --create-home --home-dir /home/opencode --user-group --shell /bin/bash opencode \
    && install -d -o opencode -g opencode /workspace

USER opencode
WORKDIR /workspace

RUN python3.11 -m venv /home/opencode/.venv \
    && python -c 'import sys; assert sys.version_info[:2] == (3, 11), sys.version; assert sys.prefix != sys.base_prefix, sys.prefix' \
    && test "$(python -m pip --version)" = "$(pip --version)" \
    && curl -fsSL https://opencode.ai/v2/install -o /tmp/opencode-install.sh \
    && bash /tmp/opencode-install.sh --version "$OPENCODE_VERSION" --no-modify-path \
    && rm -f /tmp/opencode-install.sh \
    && python -c 'import os, re, subprocess; expected = os.environ["OPENCODE_VERSION"]; actual = subprocess.check_output(["opencode", "--version"], text=True).strip(); assert re.search(r"(?<!\d)" + re.escape(expected) + r"(?!\d)", actual), f"expected {expected}, got {actual!r}"'

CMD ["opencode"]
