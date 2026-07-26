# machine-setup

One script that takes a fresh macOS or Linux machine to Paulie's baseline: Homebrew/dev
tools, GitHub CLI + login, the private [dotfiles](https://github.com/pauli3j/dotfiles)
(zsh + oh-my-zsh, tmux theme, Terminal profile), the
[obsidian-vault](https://github.com/pauli3j/obsidian-vault) with Obsidian Git seeded,
Claude Code, and the Obsidian app.

```bash
curl -fsSL https://raw.githubusercontent.com/pauli3j/machine-setup/main/setup.sh | bash
```

Idempotent — safe to re-run any time; an already-configured machine is a fast no-op.
Interactive at most twice: the sudo password and the GitHub browser login.

## What it does

| Step | macOS | Linux (apt / dnf) |
|---|---|---|
| Dev tools | Homebrew (installs Xcode CLT itself) | git, curl, build tools via the package manager |
| Base packages | via the dotfiles `Brewfile` | zsh, tmux, jq, cowsay + gh from GitHub's official repo |
| GitHub | `gh auth login` (browser) → `gh auth setup-git` | same; `GH_TOKEN` skips the prompt |
| Dotfiles | clones with submodules, then **delegates to `dotfiles/install.sh`** | clones, then mirrors it: oh-my-zsh (unattended), `~/.zshrc` + `~/.zprofile` symlinks, tmux theme into `~/.config/tmux/`, `chsh` to zsh |
| Git identity | `~/.gitconfig` include → `dotfiles/git/gitconfig` (`useConfigOnly` guardrail) | same |
| Vault | clone + seed device-local Obsidian Git `data.json` from the tracked template | same |
| Claude Code | native installer (skipped if present) — **binary only**, see step 5 | same; skipped on 32-bit ARM with a warning |
| Obsidian app | brew cask | Flatpak (flathub); skipped on headless hosts |

The script never reimplements what the dotfiles repo already does — on macOS it hands
off to `dotfiles/install.sh` (Brewfile, oh-my-zsh ordering traps, Terminal.app profile),
and on Linux it follows the documented clawscan pattern: link the tracked tmux files by
hand, put per-host identity in `~/.config/tmux/local.conf`.

## Prerequisites

- **macOS:** nothing. A factory-fresh machine works — run the one-liner in Terminal.app.
- **Linux:** `curl` and (unless root) `sudo`. Minimal containers: `apt-get update && apt-get install -y curl sudo` first.
- The dotfiles and vault repos are **private**, so the GitHub login step must succeed
  before the clones; that's why this repo is public and they aren't.

## Environment variables

| Var | Effect |
|---|---|
| `MACHINE_SETUP_PROJECTS` | where repos land (default `~/claw/projects`) |
| `GH_TOKEN` | skip interactive GitHub login (containers/CI) |
| `GH_OWNER` | GitHub account to clone from (default `pauli3j`) |
| `DOTFILES_SKIP_TERMINAL=1` etc. | passed through to `dotfiles/install.sh` on macOS |

## After it runs (manual, GUI)

1. Obsidian → "Open folder as vault" → the cloned vault → trust + enable community
   plugins. Obsidian Git then auto-backs-up every 15 min and pulls on launch.
2. macOS: **quit and reopen Terminal.app** — windows opened before the run keep their
   old profile, and the freshly installed Nerd Font only joins glyph fallback after a
   relaunch. A running tmux session survives the quit (`tmux attach` afterwards). Then
   the "Paulie" profile, banner, and tmux status-bar glyphs should render as shapes,
   not tofu boxes.
3. Linux: log out/in for the zsh login shell; optional per-host tmux colors/prefix in
   `~/.config/tmux/local.conf` (see `local.conf.example` in the tmux repo).
4. **Claude Code workspace.** The script installs the Claude Code *binary* and nothing
   else — no charter, no permission guardrails, no skills, no MCP endpoints. A machine that
   has only run this script has a Claude that does not know the house conventions and cannot
   reach any tenant. Restore, in this order:
   1. `~/.claude/CLAUDE.md` — global charter: vault pointer, writing rules, recap-on-wrap-up.
   2. `~/<hub>/CLAUDE.md` — workspace charter for the projects hub.
   3. `~/<hub>/.claude/settings.json` — **permission guardrails, including the `git init` and
      `git config --global` denials.** Not optional: those two denials exist because a work
      email once landed in a personal repo. A fresh machine has no `settings.json` at all,
      only whatever `settings.local.json` the current session has accumulated.
   4. `~/.claude/skills/` — the user-level skills.
   5. MCP endpoints — needs a per-device token; the old machine's token should be revoked
      when a machine is rebuilt.

   **Copy 1–4 from an already-configured machine rather than rewriting them** — they are
   prose that drifted into its current form deliberately, and reconstructing it from memory
   loses that. Values and the token procedure are in the private vault runbooks, not here.
5. macOS, if this machine needs the home VPN: install **WireGuard** from the Mac App
   Store (id `1451685025`) — it is not brew-installable, and `mas` cannot install an app
   the Apple ID has never acquired, so this stays manual. Then add the tunnel in the app
   and enroll its public key on the firewall. The tunnel config is deliberately **not**
   in any repo and is not symlinked out of `dotfiles` like everything else here: it
   embeds a private key. Procedure and the per-device values live in the private vault
   runbook, not in this public repo.

## Testing in a container

```bash
GH_TOKEN=$(gh auth token) docker run -e GH_TOKEN -it --rm ubuntu:24.04 bash -c '
  apt-get update && apt-get install -y curl sudo ca-certificates &&
  curl -fsSL https://raw.githubusercontent.com/pauli3j/machine-setup/main/setup.sh | bash'
```

Exercises the apt branch, token auth, root path (`SUDO=""`), headless Obsidian skip,
and the Linux Claude Code install. Swap in `fedora:latest` (with `dnf install -y curl sudo`)
for the dnf branch.

## Lint

```bash
bash -n setup.sh && shellcheck setup.sh
```
