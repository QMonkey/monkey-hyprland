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

		if ! command -v git >/dev/null 2>&1; then
			echo "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
			exit 1
		fi
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# No retry() available yet — the framework loads only after this
		# clone succeeds — so inline the standard 3 attempts. A failed clone
		# leaves a partial directory behind; remove it so the next attempt
		# cannot trip over "already exists". This branch only runs on a
		# fresh install (INSTALL_DIR did not exist or was empty), so the rm
		# can never delete pre-existing data.
		_monkey_rc=1
		for _monkey_attempt in 1 2 3; do
			if git clone "$PROJECT_REPO" "$INSTALL_DIR"; then
				_monkey_rc=0
				break
			fi
			rm -rf "$INSTALL_DIR"
			if [ "$_monkey_attempt" -lt 3 ]; then
				sleep 2
			fi
		done
		[ "$_monkey_rc" -eq 0 ] || exit 1
		fi
		# </dev/null: on the curl|bash path stdin is the script pipe, and the
		# inner installer must not read what is left of the outer one.
		exec bash "$INSTALL_DIR/install.sh" "$@" </dev/null
	fi
fi
# shellcheck source=/dev/null
. "$_monkey_scripts/install.sh"

# scripts/install.sh loads five of the seven libs. The sixth, optional.sh (the
# optional-tooling strategies: ensure_rust, ensure_npm, the cargo/go/pip
# installers), is checkhealth-scoped there — but hypr-rdp is built from source
# in this process and needs a Rust toolchain, so pull that lib in too, through
# the path the bootstrap already resolved.
# shellcheck source=/dev/null
. "$_monkey_scripts/lib/optional.sh"

# ──────────────────────── layout & data ────────────────────────
LINUX_ONLY=1
FINISH_INJECT=0 # the original writes no TIOCSTI hint — just the summary
# hypr-rdp has no package in any repo, so it is built from a source checkout
# kept outside this repo (a git clone inside a git clone would need a
# .gitignore entry and pull in ~200MB of target/).
HYPR_RDP_SRC_DIR="${HYPR_RDP_SRC_DIR:-$HOME/Documents/hypr-rdp}"
# Set by install_step_post_tool once hypr-rdp is on PATH; gates its summary
# lines ("?VAR|" entries in finish_install).
HYPR_RDP_INSTALLED=""
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
	debian | ubuntu) retry -t 1800 -s "apt-get install" sudo_cmd apt-get install -y "$@" ;;
	arch) retry -t 1800 -s "pacman install" sudo_cmd pacman -S --needed --noconfirm "$@" ;;
	opensuse) retry -t 1800 -s "zypper install" sudo_cmd zypper --non-interactive install -y "$@" ;;
	centos)
		sudo_cmd dnf install -y epel-release || true
		retry -t 1800 -s "dnf install" sudo_cmd dnf install -y "$@"
		;;
	fedora)
		retry -t 1800 -s "dnf install" sudo_cmd dnf install -y "$@"
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

# ──────────────────────── hypr-rdp (from source) ────────────────────────
# No supported repo carries hypr-rdp: upstream offers AUR, Nix and a GitHub
# release only, and that release predates the PAM-auth commit — a prebuilt
# binary would silently lose --auth-mode. Build from source instead.
#
# Runs on install_step_post_tool: it is a tool install, so it belongs next to
# the tool step, and checkhealth below then reports the result.

# Build dependencies, mirroring upstream's .github/workflows/ci.yml with
# per-distro names. The GBM and PipeWire headers sit in differently named
# packages on every distro (mesa / libgbm-devel / mesa-libgbm-devel).
# clang is not optional: pam-sys generates its bindings with bindgen, which
# links libclang (on openSUSE the clang package pulls in libclang13).
hypr_rdp_deps() {
	local deps
	case "$OS" in
	debian | ubuntu)
		deps=(
			libpipewire-0.3-dev libva-dev libxkbcommon-dev
			libwayland-dev libgbm-dev libpam0g-dev fuse3
			build-essential libclang-dev
		)
		;;
	arch) deps=(pipewire libva libxkbcommon wayland mesa pam fuse3 clang) ;;
	opensuse)
		deps=(
			pipewire-devel libva-devel libxkbcommon-devel
			wayland-devel libgbm-devel pam-devel fuse3
			gcc gcc-c++ clang
		)
		;;
	centos | fedora)
		deps=(
			pipewire-devel libva-devel libxkbcommon-devel
			wayland-devel mesa-libgbm-devel pam-devel fuse3
			gcc gcc-c++ clang-devel
		)
		;;
	*) return 1 ;;
	esac
	install_pkg "${deps[@]}"
}

# hypr-rdp builds IronRDP from git and needs a current stable Rust, which
# distro packages lag behind on. ensure_rust (scripts/lib/optional.sh) is the
# framework's own: it installs rustup when absent, sources ~/.cargo/env and
# puts ~/.cargo/bin on PATH, so plain `cargo` resolves afterwards.

clone_hypr_rdp() {
	if [ -d "$HYPR_RDP_SRC_DIR/.git" ]; then
		info "hypr-rdp source at $HYPR_RDP_SRC_DIR — pulling latest..."
		retry -s "git pull" git -C "$HYPR_RDP_SRC_DIR" pull --ff-only ||
			warn "git pull failed — building the existing checkout."
	elif [ -e "$HYPR_RDP_SRC_DIR" ]; then
		warn "$HYPR_RDP_SRC_DIR exists but is not a git clone — leaving it untouched."
		return 1
	else
		# A failed clone leaves a partial directory behind — clean it up
		# before giving up, but only when git created it (.git inside) or it
		# is empty, never when it holds pre-existing user data.
		info "Cloning hypr-rdp to $HYPR_RDP_SRC_DIR..."
		if ! retry -t 1800 -s "git clone hypr-rdp" git clone https://github.com/MuNeNICK/hypr-rdp.git "$HYPR_RDP_SRC_DIR"; then
			if [ -d "$HYPR_RDP_SRC_DIR" ] && { [ -z "$(ls -A "$HYPR_RDP_SRC_DIR")" ] || [ -d "$HYPR_RDP_SRC_DIR/.git" ]; }; then
				rm -rf "$HYPR_RDP_SRC_DIR"
			fi
			return 1
		fi
	fi
	ok "hypr-rdp source ready."
}

build_hypr_rdp() {
	info "Building hypr-rdp (release). This takes several minutes..."
	(cd "$HYPR_RDP_SRC_DIR" && retry -t 1800 -s "cargo build hypr-rdp" cargo build --release --locked) || {
		warn "cargo build failed."
		return 1
	}
	ok "hypr-rdp built."
}

# hyprland.lua's RDP section refuses to start hypr-rdp when the password file
# is missing, so a fresh machine would never bring the server up. Seed one with
# a random password. An existing file is never read, rewritten or printed.
setup_rdp_credentials() {
	local dir="$HOME/.config/hypr-rdp"
	local file="$dir/credentials"
	if [ -e "$file" ]; then
		ok "hypr-rdp credentials already present."
		return 0
	fi
	if ! have_native_cmd openssl; then
		# NEVER fatal: hypr-rdp is optional and simply won't start until a
		# password exists — killing the whole component over it cost
		# monkey-hyprland on CentOS/Fedora (no openssl CLI there).
		warn "openssl not found — hypr-rdp stays disabled until you create the RDP password yourself:"
		warn "  mkdir -p $dir && chmod 700 $dir && echo your-password >$file && chmod 600 $file"
		return 0
	fi
	mkdir -p "$dir"
	chmod 700 "$dir"
	# base64 alphabet only: dropping '/' '+' '=' keeps the value safe to
	# copy-paste through shells and config files.
	{
		openssl rand -base64 24 | tr -d '/+='
		printf '\n'
	} >"$file"
	chmod 600 "$file"
	ok "Generated an RDP password in $file"
	# Never print the value: a one-shot installer runs on shared/CI logs, and
	# the file is the only place it should ever land.
	# Four backslashes: two for the shell string, two for echo -e's own
	# escape pass — otherwise the hint prints a real newline mid-command.
	echo -e "    Read it with: ${CYAN}cat $file${NC}"
	echo -e "    Rotate it with: ${CYAN}printf '%s\\\\n' 'new-password' >$file${NC}"
}

# Never fatal: a desktop that came up without hypr-rdp is still a desktop.
install_hypr_rdp() {
	if have_native_cmd hypr-rdp; then
		ok "hypr-rdp already installed."
		setup_rdp_credentials
		HYPR_RDP_INSTALLED=1
		return 0
	fi
	case "$OS" in
	debian | ubuntu | arch | opensuse | centos | fedora) ;;
	*)
		warn "No known hypr-rdp build dependencies for $OS — skipping."
		warn "  https://github.com/MuNeNICK/hypr-rdp#build-from-source"
		return 0
		;;
	esac
	if ! hypr_rdp_deps; then
		warn "could not install hypr-rdp build dependencies — skipping the build."
		return 0
	fi
	ensure_rust || {
		warn "no Rust toolchain — skipping the hypr-rdp build."
		return 0
	}
	clone_hypr_rdp || {
		warn "no hypr-rdp source — skipping the build."
		return 0
	}
	build_hypr_rdp || return 0
	if sudo_cmd install -Dm755 "$HYPR_RDP_SRC_DIR/target/release/hypr-rdp" \
		/usr/local/bin/hypr-rdp; then
		hash -r
		ok "hypr-rdp installed to /usr/local/bin."
	else
		warn "hypr-rdp install failed."
		return 0
	fi
	setup_rdp_credentials
	HYPR_RDP_INSTALLED=1
}

# A hook prints its own trailing blank line when it produced output; the
# upstream separates setup_sudo from the first step with its own blank.
install_step_prepare() {
	echo ""
	install_hyprland
	echo ""
}

# hypr-rdp after the tool step. Its summary lines go before the trailing
# "Update:" entry rather than at the end, so the update hint stays last: split
# the array instead of hardcoding indices, which the base list's length owns.
install_step_post_tool() {
	install_hypr_rdp
	echo ""
	local -a head=("${SUMMARY_LINES[@]:0:${#SUMMARY_LINES[@]}-1}")
	SUMMARY_LINES=(
		${head[@]+"${head[@]}"}
		"?HYPR_RDP_INSTALLED|  RDP: ${CYAN}hypr-rdp${NC} autostarts with Hyprland and mirrors the focused monitor"
		"?HYPR_RDP_INSTALLED|  Edit ${CYAN}$INSTALL_DIR/rdp/config.toml.in${NC} and log back in to re-render it"
		"?HYPR_RDP_INSTALLED|  Connect any RDP client to this host on port ${CYAN}3389${NC}"
		"${SUMMARY_LINES[-1]}"
	)
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
	if [ -n "$KMSCON_TTYS" ]; then
		if is_wsl; then
			warn "WSL detected — skipping kmscon setup (no VT login)."
		else
			ensure_kmscon "$KMSCON_TTYS" || warn "kmscon setup failed — continuing without it."
			KMSCON_DONE=1
		fi
	fi
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
	if [ -n "$KMSCON_DONE" ]; then
		SUMMARY_LINES=(
			"${SUMMARY_LINES[@]:0:${#SUMMARY_LINES[@]}-1}"
			"  kmscon: fallback console on ${CYAN}${KMSCON_TTYS}${NC} — switch with chvt N"
			"${SUMMARY_LINES[-1]}"
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

# ──────────────────────── optional kmscon takeover ────────────────────────
# --with-kmscon [tty[,tty...]] hands the listed VTs to kmscon (default
# tty2) and masks the matching getty instances — ensure_kmscon in
# scripts/lib/kmscon.sh does the work. The flag stays local to this
# installer: it is parsed out here and never reaches install_main.
parse_install_args() {
	KMSCON_TTYS=""
	KMSCON_DONE=""
	local args=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--with-kmscon)
			KMSCON_TTYS=tty2
			if [[ $# -gt 1 && "$2" != --* ]]; then
				KMSCON_TTYS=$2
				shift
			fi
			;;
		*) args+=("$1") ;;
		esac
		shift
	done
	_INSTALL_ARGS=("${args[@]+"${args[@]}"}")
}

# --with-kmscon flag stays local: the parser fills _INSTALL_ARGS in this
# shell and install_main never sees the flag.
parse_install_args "$@"
install_main "${_INSTALL_ARGS[@]+"${_INSTALL_ARGS[@]}"}"
