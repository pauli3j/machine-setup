#!/usr/bin/env bash
# machine-setup — bring a fresh macOS or Linux box up to Paulie's baseline.
#
#   curl -fsSL https://raw.githubusercontent.com/pauli3j/machine-setup/main/setup.sh | bash
#
# Idempotent: every step checks before acting; re-running is a fast no-op.
# Interactive at most twice: sudo password, GitHub browser login (skipped when
# GH_TOKEN is set — the container-test path).
#
# What lands where:
#   ~/claw/projects/dotfiles        zsh + tmux + terminal config (private repo, submodule inside)
#   ~/claw/projects/obsidian-vault  the vault; Obsidian Git plugin seeded per-device
#   macOS: delegates to dotfiles/install.sh — Brewfile, oh-my-zsh, symlinks,
#          tmux theme, Terminal.app profile. This script never reimplements it.
#   Linux: mirrors the essential steps itself (dotfiles/install.sh is macOS-only)
#          and makes zsh the login shell. apt, dnf, and pacman (Arch / Omarchy).
#
# Written for bash 3.2 (macOS system bash): no associative arrays, no mapfile.
set -euo pipefail

GH_OWNER="${GH_OWNER:-pauli3j}"
PROJECTS="${MACHINE_SETUP_PROJECTS:-$HOME/claw/projects}"
DOTFILES="$PROJECTS/dotfiles"
VAULT="$PROJECTS/obsidian-vault"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- detection
OS=""; PKG=""; ARCH="$(uname -m)"; SUDO="sudo"; HEADLESS=0; ARMHF=0
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac
[ "$(id -u)" = "0" ] && SUDO=""
if [ "$OS" = linux ]; then
  if have apt-get;  then PKG=apt
  elif have dnf;    then PKG=dnf
  elif have pacman; then PKG=pacman
  else die "no supported package manager (need apt-get, dnf, or pacman)"
  fi
  case "$ARCH" in armv6l|armv7l) ARMHF=1 ;; esac
  # $DISPLAY is empty over SSH even on desktops — ask systemd / the session dirs instead.
  if [ "$(systemctl get-default 2>/dev/null || true)" = "graphical.target" ] \
     || ls /usr/share/xsessions/*.desktop >/dev/null 2>&1 \
     || ls /usr/share/wayland-sessions/*.desktop >/dev/null 2>&1; then
    HEADLESS=0
  else
    HEADLESS=1
  fi
fi

ensure_sudo() {
  [ -z "$SUDO" ] && return 0
  sudo -n true 2>/dev/null && return 0
  log "sudo needed — you may be asked for your password"
  sudo -v
}

# Symlink src -> dst, backing up a pre-existing REAL file exactly once
# (same semantics as dotfiles/install.sh; used only on the Linux path).
link() {
  [ -e "$1" ] || die "missing source: $1"
  if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then
    log "ok: $2 already linked"
    return 0
  fi
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    warn "backing up $2 -> $2.backup.machine-setup"
    mv "$2" "$2.backup.machine-setup"
  fi
  ln -sfn "$1" "$2"
  log "linked: $2 -> $1"
}

main() {

# --- 1. base packages -----------------------------------------------------------
if [ "$OS" = macos ]; then
  # Xcode CLT: the NONINTERACTIVE Homebrew installer handles a missing CLT itself,
  # but it exits immediately unless sudo credentials are already cached — prime first.
  if [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
    log "Homebrew present"
  else
    ensure_sudo
    log "installing Homebrew (this also installs the Xcode Command Line Tools)"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
  fi
  # `shellenv bash`, never `shellenv zsh` — the zsh form is a bash syntax error.
  for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$_brew" ] && { eval "$("$_brew" shellenv bash)"; break; }
  done
  # Only gh here — everything else comes from the dotfiles Brewfile in step 4.
  brew list --formula gh >/dev/null 2>&1 || brew install gh
else
  ensure_sudo
  if [ "$PKG" = apt ]; then
    $SUDO apt-get update -qq
    $SUDO apt-get install -y git curl zsh tmux jq cowsay ca-certificates unzip build-essential
    if ! have gh; then
      log "installing gh from GitHub's apt repo"
      $SUDO mkdir -p -m 755 /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
      $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      $SUDO apt-get update -qq
      $SUDO apt-get install -y gh
    fi
  elif [ "$PKG" = dnf ]; then
    $SUDO dnf install -y git curl zsh tmux jq cowsay util-linux-user gcc make unzip
    if ! have gh; then
      log "installing gh from GitHub's dnf repo"
      # dnf4 and dnf5 spell config-manager differently; try both.
      $SUDO dnf install -y 'dnf-command(config-manager)' 2>/dev/null || $SUDO dnf install -y dnf5-plugins
      $SUDO dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null \
        || $SUDO dnf config-manager addrepo --overwrite --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
      $SUDO dnf install -y gh --repo gh-cli
    fi
  else
    # Arch (and Omarchy, which is Arch underneath). Two things are simpler here
    # than on apt/dnf: the GitHub CLI is a plain [extra] package, so there is no
    # third-party repo to wire up, and chsh ships inside util-linux rather than a
    # separate package.
    #
    # NEVER `-Sy` without `-u`. Refreshing the sync db and then installing
    # without upgrading is the documented way to break an Arch box (a partial
    # upgrade links new packages against old libraries). So install against the
    # db already on disk first — the same no-refresh approach Omarchy's own
    # `omarchy pkg add` takes — and escalate to a full `-Syu` only if that fails
    # because the on-disk db is too stale to resolve a package.
    #
    # ttf-jetbrains-mono-nerd is load-bearing, not cosmetic: it carries the
    # powerline/Nerd codepoints the tmux status bar draws with. Same reason the
    # Brewfile pins the matching cask on macOS. (apt/dnf have no equivalent line
    # yet — those hosts rely on whatever Nerd Font is already present.)
    _arch_pkgs=(git curl zsh tmux jq cowsay unzip base-devel ttf-jetbrains-mono-nerd)
    # The package is named `github-cli`, NOT `gh` — `pacman -S gh` fails outright.
    # Guarded like the apt/dnf branches, and for a second reason here: mise and
    # asdf both hand out their own gh, and installing the system one over the top
    # just leaves a second binary that PATH order hides anyway.
    have gh || _arch_pkgs+=(github-cli)
    if ! $SUDO pacman -S --needed --noconfirm "${_arch_pkgs[@]}"; then
      warn "pacman could not resolve against the on-disk db — refreshing (full upgrade) and retrying"
      $SUDO pacman -Syu --needed --noconfirm "${_arch_pkgs[@]}"
    fi
  fi
fi

# --- 2. GitHub auth -------------------------------------------------------------
if [ -n "${GH_TOKEN:-}" ]; then
  log "GH_TOKEN set — skipping interactive gh login"
elif gh auth status >/dev/null 2>&1; then
  log "gh already authenticated"
else
  log "GitHub login: a one-time code will appear — enter it in the browser"
  gh auth login --hostname github.com --git-protocol https --web </dev/tty
fi
gh auth setup-git

# --- 3. dotfiles clone + git identity -------------------------------------------
mkdir -p "$PROJECTS"
if [ -d "$DOTFILES/.git" ]; then
  log "dotfiles present — updating"
  git -C "$DOTFILES" pull --ff-only || warn "could not fast-forward dotfiles"
  git -C "$DOTFILES" submodule update --init --recursive
else
  gh repo clone "$GH_OWNER/dotfiles" "$DOTFILES" -- --recurse-submodules
fi
# ~/.gitconfig stays a REAL file (git config rewrites it; a symlink would detach).
# The include brings in identity + useConfigOnly; see dotfiles/README.md.
if git config --global --get-all include.path 2>/dev/null | grep -qx "$DOTFILES/git/gitconfig"; then
  log "gitconfig include present"
else
  git config --global include.path "$DOTFILES/git/gitconfig"
  log "added ~/.gitconfig include -> dotfiles/git/gitconfig"
fi

# --- 4. shell + tmux config -----------------------------------------------------
if [ "$OS" = macos ]; then
  log "delegating to dotfiles/install.sh (Brewfile, oh-my-zsh, symlinks, tmux, Terminal profile)"
  "$DOTFILES/install.sh"
else
  # oh-my-zsh BEFORE the zshrc symlink, ZSH pinned — both traps documented in
  # dotfiles/install.sh; same invocation here.
  if [ -d "$HOME/.oh-my-zsh" ]; then
    log "oh-my-zsh present"
  else
    log "installing oh-my-zsh"
    ZSH="$HOME/.oh-my-zsh" ZSH_CUSTOM='' RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended --keep-zshrc
  fi
  link "$DOTFILES/zsh/zshrc"    "$HOME/.zshrc"
  link "$DOTFILES/zsh/zprofile" "$HOME/.zprofile"

  # tmux: theme is portable; the macOS-only parts of tmux/install.sh (brew cask,
  # Terminal.app font) don't apply, so link the tracked files by hand — the
  # documented Linux path (see tmux/CLAUDE.md, "clawscan"). Per-host colors and
  # prefix belong in ~/.config/tmux/local.conf, never in the tracked files.
  if [ -e "$HOME/.tmux.conf" ] && [ ! -L "$HOME/.tmux.conf" ]; then
    # A stray ~/.tmux.conf silently shadows ~/.config/tmux/tmux.conf entirely.
    warn "moving aside ~/.tmux.conf -> ~/.tmux.conf.shadowed-by-machine-setup"
    mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.shadowed-by-machine-setup"
  fi
  mkdir -p "$HOME/.config/tmux"
  link "$DOTFILES/tmux/tmux.conf"       "$HOME/.config/tmux/tmux.conf"
  link "$DOTFILES/tmux/tokyonight.conf" "$HOME/.config/tmux/tokyonight.conf"

  # zsh as login shell
  _zsh="$(command -v zsh)"
  _current="$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)"
  if [ "$_current" = "$_zsh" ]; then
    log "login shell already zsh"
  else
    grep -qx "$_zsh" /etc/shells || { ensure_sudo; echo "$_zsh" | $SUDO tee -a /etc/shells >/dev/null; }
    ensure_sudo
    $SUDO chsh -s "$_zsh" "${USER:-$(id -un)}"
    log "login shell -> zsh (takes effect next login)"
  fi
fi

# --- 5. Claude Code -------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
if [ "$ARMHF" = 1 ]; then
  warn "32-bit ARM OS — Claude Code needs 64-bit; skipping (reinstall the OS as arm64 to fix)"
elif have claude; then
  log "Claude Code present: $(claude --version 2>/dev/null || echo '?')"
else
  log "installing Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- 6. Obsidian vault ----------------------------------------------------------
if [ -d "$VAULT/.git" ]; then
  log "vault present — updating"
  git -C "$VAULT" pull --ff-only || warn "could not fast-forward vault"
else
  gh repo clone "$GH_OWNER/obsidian-vault" "$VAULT"
fi
# Obsidian Git plugin: binaries are committed; data.json is device-local on purpose
# (gitignored 2026-07-13) — seed it from the tracked template. See vault SETUP.md.
_plug="$VAULT/.obsidian/plugins/obsidian-git"
if [ ! -f "$_plug/main.js" ]; then
  log "obsidian-git plugin files missing — fetching latest release"
  mkdir -p "$_plug"
  _tag=$(curl -sL https://api.github.com/repos/Vinzent03/obsidian-git/releases/latest \
    | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  for _f in main.js manifest.json styles.css; do
    curl -sL -f -o "$_plug/$_f" "https://github.com/Vinzent03/obsidian-git/releases/download/$_tag/$_f"
  done
fi
if [ -f "$_plug/data.json" ]; then
  log "obsidian-git data.json present (device-local — left alone)"
else
  cp "$VAULT/_templates/obsidian-git-data.json" "$_plug/data.json"
  log "seeded device-local obsidian-git data.json (15-min auto backup, pull on boot)"
fi
# Extension point: the vault can carry extra per-machine setup snippets.
if [ -d "$VAULT/machine-setup.d" ]; then
  for _f in "$VAULT"/machine-setup.d/*.sh; do
    [ -e "$_f" ] || break
    log "vault extra: $_f"
    # shellcheck disable=SC1090
    . "$_f"
  done
fi

# --- 7. Obsidian app ------------------------------------------------------------
if [ "$OS" = macos ]; then
  if brew list --cask obsidian >/dev/null 2>&1; then
    log "Obsidian present"
  else
    brew install --cask obsidian
  fi
elif [ "$HEADLESS" = 1 ]; then
  log "headless host — skipping the Obsidian app (vault cloned for CLI/Claude use)"
else
  have flatpak || { ensure_sudo; case "$PKG" in
      apt)    $SUDO apt-get install -y flatpak ;;
      pacman) $SUDO pacman -S --needed --noconfirm flatpak ;;
      *)      $SUDO dnf install -y flatpak ;;
    esac; }
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null \
    || $SUDO flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  if flatpak info md.obsidian.Obsidian >/dev/null 2>&1; then
    log "Obsidian (flatpak) present"
  else
    flatpak install -y flathub md.obsidian.Obsidian
  fi
fi

# --- 8. Claude workspace + VPN (optional add-on) --------------------------------
# Opt in:  MACHINE_SETUP_WORKSPACE=1
# Off by default — a plain bootstrap shouldn't write permission policy.
#
# THIS REPO IS PUBLIC. Nothing secret goes in this block: no endpoints, tokens,
# tunnel addresses, or charter prose. Those live in the private vault — drop a
# snippet in $VAULT/machine-setup.d/*.sh (sourced in step 6) and it runs with all
# the private values available, without ever touching this file.
#
# What this can legitimately automate is small: the directory skeleton and the
# permission guardrails. The rest is prose to copy and a token to mint, both of
# which need a human and a second machine.
if [ "${MACHINE_SETUP_WORKSPACE:-0}" = 1 ]; then
  HUB="$(dirname "$PROJECTS")"
  log "workspace add-on: scaffolding $HUB"
  mkdir -p "$HUB/reports" "$HUB/scratch" "$HOME/.claude/skills"

  # Permission guardrails. `git init` and `git config --global` are denied because
  # an unconfigured git INVENTS a user@hostname identity rather than erroring
  # (useConfigOnly), and that once put a work email in a personal repo. A machine
  # with no settings.json has no such deny — only whatever settings.local.json a
  # session has accumulated, which is not a policy.
  _ws="$HUB/.claude/settings.json"
  if [ -f "$_ws" ]; then
    log "workspace settings.json present — left alone (never clobber policy)"
  else
    mkdir -p "$HUB/.claude"
    cat > "$_ws" <<'JSON'
{
  "permissions": {
    "deny": [
      "Bash(git init)",
      "Bash(git init:*)",
      "Bash(git config --global:*)"
    ]
  }
}
JSON
    log "wrote permission guardrails -> $_ws"
  fi

  echo
  echo "Workspace add-on — what still needs a human:"
  echo "  a. Copy from an already-configured machine (do NOT rewrite from memory):"
  echo "       ~/.claude/CLAUDE.md          global charter + writing rules"
  echo "       $HUB/CLAUDE.md    workspace charter"
  echo "       ~/.claude/skills/            user-level skills"
  echo "  b. MCP endpoints: mint this device its own token and register the tenants."
  echo "     Revoke the old entry if this machine was rebuilt. Procedure lives in the"
  echo "     private vault runbook, not here."
  if [ "$OS" = macos ] && [ ! -d /Applications/WireGuard.app ]; then
    echo "  c. WireGuard: install from the Mac App Store (id 1451685025) — not"
    echo "     brew-installable, and 'mas' can't install an app this Apple ID has"
    echo "     never acquired. Then add the tunnel and enroll its public key."
    echo "     The tunnel config stays out of every repo: it embeds a private key."
  fi
  echo
fi

# --- done -----------------------------------------------------------------------
log "machine-setup complete"
echo
echo "Manual steps that need a human + GUI:"
echo "  1. Obsidian: open '$VAULT' as a vault, trust it, enable community plugins."
echo "     (Obsidian Git then auto-syncs every 15 min and pulls on launch.)"
if [ "$OS" = macos ]; then
  echo "  2. Quit and REOPEN Terminal.app (first run only): open windows keep their old"
  echo "     profile, and glyph fallback into the just-installed Nerd Font needs the"
  echo "     relaunch. A tmux session survives the quit — 'tmux attach' afterwards."
  echo "     Then confirm the status-bar pills draw as shapes, not tofu boxes."
else
  echo "  2. Log OUT and back in to pick up the new login shell. 'exec zsh' fixes"
  echo "     only the shell you type it in — two things cache the old one and both"
  echo "     outlive chsh: a RUNNING tmux server keeps the default-shell it detected"
  echo "     when it started, and the systemd user session carries its own SHELL,"
  echo "     which is what a terminal launched from the desktop inherits. So new"
  echo "     windows go on spawning the old shell until you log out."
  echo "     To skip the logout, fix both in place:"
  echo '       tmux set -g default-shell "$(command -v zsh)"'
  echo '       systemctl --user set-environment SHELL="$(command -v zsh)"'
  echo "     Optional: per-host tmux identity in ~/.config/tmux/local.conf (see local.conf.example)."
fi
}

main "$@"
