FROM ubuntu:24.04
# To pin by digest, replace with:
#   FROM ubuntu:24.04@sha256:<digest>
# Get current digest: docker pull ubuntu:24.04 && docker inspect ubuntu:24.04 --format '{{index .RepoDigests 0}}'

# 1. Core system packages — rarely changes
# bubblewrap is required by CLAUDE_CODE_SUBPROCESS_ENV_SCRUB when enabled.
RUN apt-get update && apt-get install -y \
    curl git zsh python3 python3-pip libsecret-1-0 gnome-keyring dbus-x11 tmux \
    ripgrep fd-find fzf jq sqlite3 make parallel entr bat tree procps bubblewrap \
    && rm -rf /var/lib/apt/lists/*
# Note: libsecret-1-0 gnome-keyring dbus-x11 are still needed for Claude Code OAuth token storage.
# If a future Claude Code version stores credentials entirely in ~/.claude/ flat files, these can
# be removed along with the D-Bus bootstrap in entrypoint.sh and the claude-sandbox-keyrings volume.

# 2. GitHub CLI — rarely changes (own apt repo)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# 3. Create claude user — basically never changes
RUN useradd -m -s /bin/zsh claude

# 4. Node.js 22 LTS — pinned to major; update to setup_24.x when Node 24 becomes LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# 5. Playwright system dependencies (root-level apt packages only)
# yq kept for YAML parsing in scripts; Python playwright dropped — use Node playwright instead.
RUN pip3 install yq --break-system-packages && \
    npx playwright install-deps chromium && \
    rm -rf /var/lib/apt/lists/*

# 6. Git wrapper — occasional changes (security rule edits)
COPY container-files/git-wrapper.sh /usr/local/bin/git
RUN chmod +x /usr/local/bin/git

# 7. Entrypoint and hooks — occasional changes
COPY --chown=claude:claude container-files/entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh
COPY --chown=claude:claude container-files/hooks/ /home/claude/hooks/
RUN chmod +x /home/claude/hooks/*.sh

# Switch to unprivileged user for all remaining steps
USER claude
WORKDIR /workspace

# Pre-create keyrings dir as claude so named volume inherits correct ownership
RUN mkdir -p /home/claude/.local/share/keyrings

# 8. Playwright browser binary (user-level, Node only)
# Placed before Claude Code install so Claude updates don't force browser re-downloads.
RUN npx playwright install chromium

# 9. Claude Code CLI — version injected by build.sh (fetches latest from GitHub); fallback ARG used only for direct docker build calls
ARG CLAUDE_CODE_VERSION=2.1.138
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}" && \
    /home/claude/.local/bin/claude --version
ENV PATH="/home/claude/.local/bin:$PATH"

# Use bundled CAs and disable background cron jobs.
# CERT_STORE=bundled: ignore OS CA store (defense against tampered host CA bundle).
# DISABLE_CRON: no background scheduled jobs in an interactive sandbox session.
#
# Note on CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: disabled by default (=0) because bubblewrap
# cannot create namespaces under `--cap-drop ALL` + `--security-opt no-new-privileges`.
# bubblewrap is installed above so it's available if you want to opt in by:
#   (a) setting CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 here, AND
#   (b) relaxing the Docker caps in claude-sandbox.sh (add --cap-add SYS_ADMIN or drop
#       --security-opt no-new-privileges; each loses some container-level isolation).
# The Docker-level sandbox already bounds subprocess environment risk, so defaulting off
# is a reasonable tradeoff.
ENV CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=0 \
    CLAUDE_CODE_CERT_STORE=bundled \
    CLAUDE_CODE_DISABLE_CRON=1 \
    REFERENCES=/references

# 10. Claude instructions and settings — most volatile, always last
COPY --chown=claude:claude container-files/CLAUDE-root.md /home/claude/.claude/CLAUDE.md
COPY --chown=claude:claude container-files/settings.json /home/claude/.claude/settings.json
COPY --chown=claude:claude container-files/tmux.conf /home/claude/.tmux.conf
