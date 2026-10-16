FROM registry.fedoraproject.org/fedora:44@sha256:74e857c33dfb387710b2b1a0203824351a25e9844356af2d1e5792ca2a96129b

# renovate: datasource=npm depName=@opencode/cli
ARG OPENCODE_VERSION=2.0.31
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=2.102.0
# renovate: datasource=gitlab-releases depName=gitlab-org/cli
ARG GLAB_VERSION=1.123.0
# renovate: datasource=pypi depName=mcp-atlassian
ARG MCP_ATLASSIAN_VERSION=0.23.1
# renovate: datasource=npm depName=oh-my-opencode-slim
ARG OH_MY_OPENCODE_SLIM_VERSION=3.0.4

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

# Dedicated venv keeps the Jira MCP server isolated from the user's ~/.venv.
RUN python3.11 -m venv /opt/mcp-atlassian \
    && /opt/mcp-atlassian/bin/pip install --no-cache-dir "mcp-atlassian==${MCP_ATLASSIAN_VERSION}" \
    && /opt/mcp-atlassian/bin/mcp-atlassian --version

COPY --chmod=0755 scripts/mcp-atlassian-jira.sh /usr/local/bin/mcp-atlassian-jira

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
    && python -c 'import os, re, subprocess; expected = os.environ["OPENCODE_VERSION"]; actual = subprocess.check_output(["opencode", "--version"], text=True).strip(); assert re.search(r"(?<!\d)" + re.escape(expected) + r"(?!\d)", actual), f"expected {expected}, got {actual!r}"' \
    && opencode plugin add "oh-my-opencode-slim@${OH_MY_OPENCODE_SLIM_VERSION}"

CMD ["opencode"]
