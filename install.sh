#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-hyprland one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-hyprland/master/install.sh | bash
#
# Installs Hyprland from the distro repo when its version supports the Lua
# config API (>= 0.55), installs the remaining dependencies via
# checkhealth.sh --install, clones this repo and links the configs, and
# writes a guarded VT autostart block into the shell profile files
# (the meta-installer's dependency order puts the compositor before tmux,
# so the block lands above any tmux auto-start block).
#
# The shared installer (sudo, packages, clone, checkhealth, symlinks,
# completion) lives in scripts/ — a `git subtree` of
# github.com/QMonkey/monkey-scripts. On the curl|bash path there is no
# checkout at all, so install.sh clones THIS repo and runs the copy of
# install.sh inside it — that copy carries its own scripts/, so the
# installer and the framework it loads are always the same revision.
# ──────────────────────────────────────────────────────────────

# ──────────────────────── repository identity ────────────────────────
# Declared before the framework is sourced: the bootstrap below needs both
# values, and clones into the very directory clone_monkey_project would
# have used — one clone per run, not two.
PROJECT=monkey-hyprland
PROJECT_REPO=https://github.com/QMonkey/monkey-hyprland.git
INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-hyprland}"

# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on) or `curl | bash`, which has no checkout
# at all. The latter clones THIS project and runs the install.sh from that
# checkout, so installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		git -C "$_monkey_dir" pull --ff-only || true
		_monkey_scripts="$_monkey_dir/scripts"
		if [ ! -f "$_monkey_scripts/install.sh" ]; then
			echo "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			echo "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
	else
		# curl|bash: no checkout at all. Get one that carries scripts/ and
		# hand over to its installer, so install.sh and scripts/ can never be
		# different revisions. clone_monkey_project cannot do this job — it
		# lives in the very scripts/ being fetched. INSTALL_DIR is where the
		# framework's clone step would have put the checkout too, so that step
		# only confirms it.
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			git clone "$PROJECT_REPO" "$INSTALL_DIR" || exit 1
		fi
		# </dev/null: on the curl|bash path stdin is the script pipe, and the
		# inner installer must not read what is left of the outer one.
		exec bash "$INSTALL_DIR/install.sh" "$@" </dev/null
	fi
fi
# shellcheck source=/dev/null
. "$_monkey_scripts/install.sh"

# ──────────────────────── layout & data ────────────────────────
LINUX_ONLY=1
FINISH_INJECT=0 # the original writes no TIOCSTI hint — just the summary
SUMMARY_LINES=(
	"  Config: ${CYAN}$INSTALL_DIR${NC} → ${CYAN}~/.config/hypr + ~/.config/waybar${NC}"
	"  Start Hyprland from a TTY (never under sudo/root): ${CYAN}start-hyprland${NC} (or ${CYAN}Hyprland${NC} on older builds)"
	"  Update: ${CYAN}cd $INSTALL_DIR && git pull && hyprctl reload${NC}"
)

# ──────────────────────── project steps ────────────────────────

# Upstream installer semantics: skip packages the system already has
# (pacman --needed). Overrides the shared install_pkg for this script only
# (checkhealth.sh runs in its own process). Keys on OS, which is one
# id per distro: Ubuntu and Fedora have their own rows here.
install_pkg() {
	refresh_pkg
	local rc=0
	case "$OS" in
	debian | ubuntu) sudo_cmd apt-get install -y "$@" ;;
	arch) sudo_cmd pacman -S --needed --noconfirm "$@" ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "$@" ;;
	centos)
		sudo_cmd dnf install -y epel-release || true
		sudo_cmd dnf install -y "$@"
		;;
	fedora)
		sudo_cmd dnf install -y "$@"
		;;
	*) rc=1 ;;
	esac || rc=$?
	hash -r
	return "$rc"
}

# Version of the hyprland package in the DISTRO REPO (not the installed
# one): X.Y or empty when the repo has no such package.
repo_hyprland_version() {
	local ver=""
	case "$OS" in
	debian | ubuntu) ver=$(apt-cache policy hyprland 2>/dev/null | awk '/Candidate:/{print $2}') ;;
	arch) ver=$(LC_ALL=C pacman -Si hyprland 2>/dev/null | awk '/^Version[[:space:]]*:/ {print $3; exit}') ;;
	opensuse) ver=$(LC_ALL=C zypper --non-interactive info hyprland 2>/dev/null | awk -F': *' '/^Version/{print $2; exit}') ;;
	centos | fedora) ver=$(dnf -q list available hyprland 2>/dev/null | awk 'NR>1 {print $2; exit}') ;;
	esac
	printf '%s' "$ver" | grep -oE '^[0-9]+\.[0-9]+' || true
}

manual_build_hint() {
	warn "Hyprland needs a manual build (requires gcc >= 16 or clang >= 19):"
	warn "  https://wiki.hyprland.org/Getting-Started/Installation/#manual-build"
	warn "Always update via git pull + git submodule update --init --recursive + rebuild."
}

install_hyprland() {
	if have_native_cmd Hyprland || have_native_cmd hyprctl; then
		ok "Hyprland already installed."
		return 0
	fi
	local ver
	ver=$(repo_hyprland_version)
	if [[ -z "$ver" ]]; then
		warn "Hyprland is not available in the $OS repositories."
		manual_build_hint
		return 0
	fi
	local major=${ver%%.*} minor=${ver#*.}
	if ((major == 0 && minor < 55)); then
		warn "Repository Hyprland ${ver} is older than 0.55 — no Lua config API (hl), the config will not load."
		manual_build_hint
		return 0
	fi
	info "Installing Hyprland ${ver} from the $OS repository..."
	if ! install_pkg hyprland; then
		warn "hyprland install failed."
		manual_build_hint
		return 0
	fi
	ok "Hyprland installed."
}

# A hook prints its own trailing blank line when it produced output; the
# upstream separates setup_sudo from the first step with its own blank.
install_step_prepare() {
	echo ""
	install_hyprland
	echo ""
}

# The compositor autostart line of the summary depends on what
# write_tty_autostart did — slot it in before "Update:".
install_step_autostart() {
	# The watchdog launcher ships with recent Hyprland builds; fall back to
	# the plain binary on older ones.
	local launcher=Hyprland
	command -v start-hyprland >/dev/null 2>&1 && launcher=start-hyprland
	# pgrep matches the compositor process name, not the launcher: the
	# start-hyprland watchdog execs into Hyprland either way.
	write_tty_autostart "$launcher" Hyprland
	echo ""
	if [ -n "$AUTOSTART_FILES" ]; then
		SUMMARY_LINES=(
			"${SUMMARY_LINES[0]}"
			"${SUMMARY_LINES[1]}"
			"  Autostart: a VT login execs ${CYAN}${launcher}${NC} unless Hyprland is already running (block in:${CYAN}${AUTOSTART_FILES}${NC})"
			"${SUMMARY_LINES[2]}"
		)
	fi
}

# hyprland's links are reported with the full destination path and never
# re-created under an existing entry — the original's own helpers, kept
# verbatim (they override the shared setup_symlinks / link_config).
link_config() {
	# Usage: link_config <src> <dst>. Never overwrites an existing target
	# that is not this repo's link (ln -sfn into a real directory would
	# create the link INSIDE it).
	local src="$1" dst="$2"
	if [ -e "$dst" ] || [ -L "$dst" ]; then
		if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
			ok "$(basename "$dst") already linked."
		else
			warn "$dst exists and is not this repo's link — skipping."
			echo -e "    re-link manually with: ${CYAN}ln -sfn $src $dst${NC}"
		fi
		return 0
	fi
	ln -sfn "$src" "$dst"
	ok "$dst → $src"
}

setup_symlinks() {
	info "Setting up configuration symlinks..."
	mkdir -p "$HOME/.config"
	link_config "$INSTALL_DIR" "$HOME/.config/hypr"
	link_config "$INSTALL_DIR/waybar" "$HOME/.config/waybar"
	link_config "$INSTALL_DIR/wlogout" "$HOME/.config/wlogout"
}

install_main "$@"
