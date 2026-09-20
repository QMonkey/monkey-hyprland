#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="[${GREEN}✓${NC}]"
FAIL="[${RED}✗${NC}]"
WARN="[${YELLOW}!${NC}]"

ALL_PASSED=true
INSTALL_MODE=false
SKIP_CONFIG_CHECKS=false

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Check and optionally install dependencies for monkey-hyprland.

OPTIONS
  -i, --install    Install missing dependencies
  --skip-check-config
                   Skip config-file checks (install.sh passes this: the
                   config symlinks are linked after this script runs)
  -h, --help       Show this help

Exit code: 1 if any required dependency is missing, 0 otherwise.
EOF
	exit 0
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --install) INSTALL_MODE=true ;;
		--skip-check-config) SKIP_CONFIG_CHECKS=true ;;
		-h | --help) usage ;;
		*)
			echo "Unknown option: $1"
			usage
			;;
		esac
		shift
	done
}

# ──────────────────────────── helpers ────────────────────────────

# WSL interop appends the WINDOWS PATH to ours, so tools installed on the
# Windows side appear as /mnt/c/... shims. They are NOT Linux binaries —
# treat /mnt/* resolutions as "not installed" so the real Linux packages
# get installed instead.
have_native_cmd() {
	command -v "$1" &>/dev/null || return 1
	case "$(command -v "$1")" in
	/mnt/*) return 1 ;; # WSL Windows-interop shim
	esac
	return 0
}

# Absolute path to a LINUX sudo, or non-zero.
native_sudo() {
	local p
	have_native_cmd sudo || return 1
	p=$(command -v sudo)
	printf '%s' "$p"
}

sudo_cmd() {
	# Lazy re-auth: sudo tickets expire (and brew resets them) —
	# re-authenticate proactively with an explanatory prompt instead of
	# letting a command fail or spring a context-free password prompt.
	# `-n true` never prompts; the interactive `-v` only runs when the
	# ticket is actually gone.
	local sudo_bin
	sudo_bin=$(native_sudo) || {
		"$@"
		return
	}
	if ! "$sudo_bin" -n true 2>/dev/null; then
		"$sudo_bin" -v -p "[monkey-hyprland] sudo credentials needed to continue — enter your password: " || return 1
	fi
	"$sudo_bin" "$@"
}

check_bin() {
	if have_native_cmd "$1"; then
		echo -e "  ${PASS} ${2:-$1}"
		return 0
	else
		echo -e "  ${FAIL} ${2:-$1}"
		return 1
	fi
}

# Same as check_bin but accepts multiple alternatives and falls back to
# /usr/lib and /usr/libexec (D-Bus services such as the desktop portals and
# polkit agents usually live outside PATH).
check_bin_ext() {
	local label="$1"
	shift
	for b in "$@"; do
		if have_native_cmd "$b" || [[ -x "/usr/lib/$b" ]] || [[ -x "/usr/libexec/$b" ]]; then
			echo -e "  ${PASS} $label ($b)"
			return 0
		fi
	done
	echo -e "  ${FAIL} $label"
	return 1
}

# Pure availability test used after --install: PATH or /usr/lib* lookup.
bin_req_ok() {
	local b="$1"
	if [[ "$b" == "notif" ]]; then
		have_native_cmd mako && return 0
		have_native_cmd dunst && return 0
		return 1
	fi
	if have_native_cmd "$b"; then return 0; fi
	for p in "/usr/lib/$b" "/usr/libexec/$b"; do
		[[ -x "$p" ]] && return 0
	done
	return 1
}

os_detect() {
	case "$(uname -s)" in
	Linux)
		if [ -f /etc/os-release ]; then
			# shellcheck disable=SC1091
			. /etc/os-release
			case "$ID" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
			opensuse | opensuse-leap | opensuse-tumbleweed | opensuse-microos | suse | sles) echo "opensuse" ;;
			centos | rhel | fedora | rocky | almalinux | ol) echo "centos" ;;
			*) echo "linux-unknown" ;;
			esac
		else
			echo "linux-unknown"
		fi
		;;
	*) echo "unknown" ;;
	esac
}

# ────────────────── package index refresh ──────────────────
# Refresh the package index before installing: a stale or missing index is
# the usual cause of "Unable to locate package" on freshly provisioned
# machines. Retried once for transient network failures; a failed refresh
# is never fatal — the install step still runs. Guarded to at most one
# refresh per run — call freely before every install.
PKG_DB_REFRESHED=0
refresh_pkg() {
	[ "$PKG_DB_REFRESHED" -eq 1 ] && return 0
	PKG_DB_REFRESHED=1
	local attempt
	for attempt in 1 2; do
		case "$OS" in
		debian) sudo_cmd apt-get update ;;
		arch) sudo_cmd pacman -Sy ;;
		opensuse) sudo_cmd zypper --non-interactive refresh ;;
		centos) sudo_cmd dnf makecache -q ;;
		*) return 0 ;;
		esac && return 0
		[ "$attempt" -lt 2 ] && sleep 2
	done
	return 0
}

install_pkg() {
	if ! $INSTALL_MODE; then return 1; fi
	refresh_pkg
	local _rc=0
	case "$OS" in
	debian) sudo_cmd apt-get install -y "$@" || _rc=1 ;;
	arch) sudo_cmd pacman -S --noconfirm "$@" || _rc=1 ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "$@" || _rc=1 ;;
	centos)
		# Some of the tools come from EPEL on the RHEL/Fedora family.
		sudo_cmd dnf install -y epel-release || true
		sudo_cmd dnf install -y "$@" || _rc=1
		;;
	*) return 1 ;;
	esac
	# Re-scan PATH: fresh binaries must not be shadowed by bash's
	# per-process command hash cache. Run AFTER capturing _rc — hash -r
	# must not mask the install status.
	hash -r
	return "$_rc"
}

get_install_hint() {
	case "$OS" in
	debian) echo "sudo apt-get install ${*}" ;;
	opensuse) echo "sudo zypper install ${*}" ;;
	centos) echo "sudo dnf install ${*}" ;;
	arch) echo "sudo pacman -S ${*}" ;;
	*) echo "install ${*} manually" ;;
	esac
}

# ────────────────── dependency definitions ──────────────────

REQUIRED_BINS=(hyprctl waybar wezterm wofi grim slurp wl-copy wlogout wpctl hyprpaper hypridle fcitx5)
# D-Bus services that may live outside PATH (/usr/lib, /usr/libexec). "notif"
# is special: it accepts mako OR dunst (any one notification daemon).
REQUIRED_EXT_BINS=(xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent notif)
RECOMMENDED_BINS=(nm-applet hyprlock brightnessctl pavucontrol nm-connection-editor hyprpicker hyprsunset hyprland-dialog)

# Human-readable name for a dependency binary.
dep_name() {
	case "$1" in
	hyprctl) echo "hyprctl (ships with Hyprland)" ;;
	wezterm) echo "wezterm (default terminal)" ;;
	wofi) echo "wofi (app launcher)" ;;
	grim) echo "grim (screenshot)" ;;
	slurp) echo "slurp (region select)" ;;
	wl-copy) echo "wl-clipboard (wl-copy)" ;;
	wlogout) echo "wlogout (power menu)" ;;
	wpctl) echo "wireplumber (wpctl)" ;;
	hyprpaper) echo "hyprpaper (wallpaper)" ;;
	hypridle) echo "hypridle (idle management)" ;;
	fcitx5) echo "fcitx5 (input method framework)" ;;
	xdg-desktop-portal-hyprland) echo "xdg-desktop-portal-hyprland (capture/sharing portal)" ;;
	xdg-desktop-portal-gtk) echo "xdg-desktop-portal-gtk (file-chooser portal)" ;;
	hyprpolkitagent) echo "hyprpolkitagent (polkit auth agent)" ;;
	notif) echo "notification daemon (mako/dunst)" ;;
	nm-applet) echo "nm-applet (tray network manager)" ;;
	hyprlock) echo "hyprlock (lock screen)" ;;
	hyprpicker) echo "hyprpicker (color picker)" ;;
	hyprsunset) echo "hyprsunset (color temperature)" ;;
	nm-connection-editor) echo "nm-connection-editor" ;;
	hyprland-dialog) echo "hyprland-guiutils (GUI helper dialogs/run/welcome)" ;;
	*) echo "$1" ;;
	esac
}

# Package name for a binary on the detected OS. Only entries that differ
# from the binary name need a case arm; everything else falls through.
pkg_name() {
	local bin="$1"
	case "$OS:$bin" in
	# Sentinel: notification daemon — install mako by default
	*:notif) echo "mako" ;;
	# Debian / apt
	debian:wl-copy) echo "wl-clipboard" ;;
	debian:wpctl) echo "wireplumber" ;;
	debian:nm-applet) echo "network-manager-gnome" ;;
	debian:nm-connection-editor) echo "nm-connection-editor" ;;
	# Arch / pacman
	arch:wl-copy) echo "wl-clipboard" ;;
	arch:wpctl) echo "wireplumber" ;;
	arch:nm-applet) echo "network-manager-applet" ;;
	arch:nm-connection-editor) echo "nm-connection-editor" ;;
	# openSUSE / zypper
	opensuse:wl-copy) echo "wl-clipboard" ;;
	opensuse:wpctl) echo "wireplumber" ;;
	opensuse:nm-applet) echo "NetworkManager-applet" ;;
	opensuse:nm-connection-editor) echo "NetworkManager-connection-editor" ;;
	# CentOS-family / dnf
	centos:wl-copy) echo "wl-clipboard" ;;
	centos:wpctl) echo "wireplumber" ;;
	centos:nm-applet) echo "NetworkManager-applet" ;;
	*:hyprland-dialog) echo "hyprland-guiutils" ;;
	*)
		echo "$bin"
		;;
	esac
}

# ──────────────────── phases ────────────────────

print_header() {
	echo -e "${BOLD}monkey-hyprland dependency check${NC}"
	echo ""
	echo -e "${BOLD}Hyprland version${NC}"
	if have_native_cmd Hyprland; then
		local out ver major minor
		out=$(Hyprland --version 2>/dev/null)
		ver=$(echo "$out" | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)
		if [[ -n "$ver" ]]; then
			major=${ver%%.*}
			minor=$(echo "$ver" | cut -d. -f2)
			if ((major > 0 || (major == 0 && minor >= 55))); then
				echo -e "  ${PASS} Hyprland ${ver}"
			else
				echo -e "  ${FAIL} Hyprland ${ver} (need >= 0.55 for Lua config support)"
				ALL_PASSED=false
			fi
		else
			echo -e "  ${PASS} Hyprland (version string unparsable: $(echo "$out" | head -1))"
		fi
		if echo "$out" | grep -qi lua; then
			echo -e "  ${PASS} Lua config support built in"
		else
			echo -e "  ${WARN} version string does not mention Lua — check that your build supports the hl Lua config API"
		fi
	elif have_native_cmd hyprctl; then
		echo -e "  ${WARN} Hyprland binary not found, but hyprctl is available"
	else
		echo -e "  ${FAIL} Hyprland (not found)"
		ALL_PASSED=false
	fi
	echo ""
}

print_platform() {
	echo -e "${BOLD}Platform${NC}"
	echo -e "  OS: ${CYAN}$(uname -s)${NC}"
	case "$OS" in
	debian) echo -e "  Package manager: ${CYAN}apt${NC}" ;;
	opensuse) echo -e "  Package manager: ${CYAN}zypper${NC}" ;;
	centos) echo -e "  Package manager: ${CYAN}dnf${NC}" ;;
	arch) echo -e "  Package manager: ${CYAN}pacman${NC}" ;;
	*) echo -e "  ${WARN} Unsupported OS — install dependencies manually" ;;
	esac
	echo ""
}

# Sets MISSING_REQUIRED.
check_required_tools() {
	echo -e "${BOLD}Required tools${NC}"
	echo "  (compositor/bar/terminal/launcher/screenshot/portals/polkit/notif/audio/wallpaper/idle/input method)"
	MISSING_REQUIRED=()
	local bin candidates
	for bin in "${REQUIRED_BINS[@]}"; do
		if check_bin "$bin" "$(dep_name "$bin")"; then
			:
		else
			MISSING_REQUIRED+=("$bin")
		fi
	done
	for bin in "${REQUIRED_EXT_BINS[@]}"; do
		if [[ "$bin" == "notif" ]]; then
			candidates=("mako" "dunst")
		else
			candidates=("$bin")
		fi
		if check_bin_ext "$(dep_name "$bin")" "${candidates[@]}"; then
			:
		else
			MISSING_REQUIRED+=("$bin")
		fi
	done
	echo ""
}

install_missing_required() {
	if ! $INSTALL_MODE || [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
		return 0
	fi
	echo -e "${YELLOW}Installing: ${MISSING_REQUIRED[*]}...${NC}"
	local pkgs=() b
	for b in "${MISSING_REQUIRED[@]}"; do pkgs+=("$(pkg_name "$b")"); done
	if install_pkg "${pkgs[@]}"; then
		MISSING_REQUIRED=()
		for b in "${REQUIRED_BINS[@]}" "${REQUIRED_EXT_BINS[@]}"; do
			if bin_req_ok "$b"; then
				echo -e "  ${PASS} $(dep_name "$b") installed"
			else
				MISSING_REQUIRED+=("$b")
				echo -e "  ${FAIL} $(dep_name "$b") still missing"
			fi
		done
		if [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
			echo -e "${GREEN}All required tools now available.${NC}"
		else
			echo -e "${RED}Not in system repos — install manually: wezterm (https://wezterm.org/installation), hyprlock (https://github.com/hyprwm/hyprlock), xdg-desktop-portal-hyprland, hyprpolkitagent, hyprpaper, hypridle (on Arch all of these are in the official repo)${NC}"
		fi
	else
		echo -e "${RED}Install command failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
	fi
	echo ""
}

# Sets MISSING_RECOMMENDED.
check_recommended_tools() {
	echo -e "${BOLD}Recommended tools${NC}"
	echo "  (Missing won't block monkey-hyprland, but will degrade tray / lock / brightness / gui-dialog experience)"
	MISSING_RECOMMENDED=()
	local bin
	for bin in "${RECOMMENDED_BINS[@]}"; do
		if check_bin "$bin" "$(dep_name "$bin")"; then
			:
		else
			MISSING_RECOMMENDED+=("$bin")
		fi
	done
	echo ""
}

install_missing_recommended() {
	if ! $INSTALL_MODE || [[ ${#MISSING_RECOMMENDED[@]} -eq 0 ]]; then
		return 0
	fi
	echo -e "${YELLOW}Installing: ${MISSING_RECOMMENDED[*]}...${NC}"
	local pkgs=() b
	for b in "${MISSING_RECOMMENDED[@]}"; do pkgs+=("$(pkg_name "$b")"); done
	if install_pkg "${pkgs[@]}"; then
		echo -e "${GREEN}Done.${NC}"
	else
		echo -e "${RED}Failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
	fi
	echo ""
}

check_fonts() {
	echo -e "${BOLD}Fonts (optional)${NC}"
	echo "  (waybar icons use Nerd Font glyphs)"
	if fc-list 2>/dev/null | grep -qi "nerd"; then
		echo -e "  ${PASS} Nerd Font found"
	else
		echo -e "  ${WARN} No Nerd Font detected — waybar icons may render as boxes"
		echo -e "    https://github.com/ryanoasis/nerd-fonts"
	fi
	echo ""
}

check_config_files() {
	# --skip-check-config (passed by install.sh): the config symlinks are
	# linked AFTER this script runs, so judging them here would fail every
	# chained run and burn all three retries. Standalone runs (the manual
	# diagnosis entry point) still get the full check.
	if $SKIP_CONFIG_CHECKS; then
		echo -e "  ${WARN} config checks skipped (handled by the installer)"
		return 0
	fi
	echo -e "${BOLD}Config files${NC}"
	local script_dir
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

	local hypr_config="${HOME}/.config/hypr/hyprland.lua"
	if [[ -L "$hypr_config" ]]; then
		local target
		target=$(readlink -f "$hypr_config" 2>/dev/null || readlink "$hypr_config")
		echo -e "  ${PASS} hyprland.lua → ${target}"
	elif [[ -f "$hypr_config" ]]; then
		echo -e "  ${WARN} hyprland.lua exists but is not a symlink"
	else
		echo -e "  ${FAIL} hyprland.lua not found (run: ln -sf ${script_dir}/hyprland.lua ~/.config/hypr/hyprland.lua)"
		ALL_PASSED=false
	fi

	local hypr_lock="${HOME}/.config/hypr/hyprlock.conf"
	if [[ -L "$hypr_lock" ]]; then
		local lock_target
		lock_target=$(readlink -f "$hypr_lock" 2>/dev/null || readlink "$hypr_lock")
		echo -e "  ${PASS} hyprlock.conf → ${lock_target}"
	elif [[ -f "$hypr_lock" ]]; then
		echo -e "  ${WARN} hyprlock.conf exists but is not a symlink"
	else
		echo -e "  ${FAIL} hyprlock.conf not found (run: ln -sf ${script_dir}/hyprlock.conf ~/.config/hypr/hyprlock.conf)"
		ALL_PASSED=false
	fi

	local hypr_idle="${HOME}/.config/hypr/hypridle.conf"
	if [[ -L "$hypr_idle" ]]; then
		local idle_target
		idle_target=$(readlink -f "$hypr_idle" 2>/dev/null || readlink "$hypr_idle")
		echo -e "  ${PASS} hypridle.conf → ${idle_target}"
	elif [[ -f "$hypr_idle" ]]; then
		echo -e "  ${WARN} hypridle.conf exists but is not a symlink"
	else
		echo -e "  ${FAIL} hypridle.conf not found (run: ln -sf ${script_dir}/hypridle.conf ~/.config/hypr/hypridle.conf)"
		ALL_PASSED=false
	fi

	local waybar_dir="${HOME}/.config/waybar"
	if [[ -L "$waybar_dir" ]]; then
		local target
		target=$(readlink -f "$waybar_dir" 2>/dev/null || readlink "$waybar_dir")
		echo -e "  ${PASS} waybar → ${target}"
	elif [[ -f "$waybar_dir/config.jsonc" && -f "$waybar_dir/style.css" ]]; then
		if [[ -f "${script_dir}/waybar/config.jsonc" && "$waybar_dir/config.jsonc" -ef "${script_dir}/waybar/config.jsonc" ]]; then
			echo -e "  ${PASS} waybar → ${script_dir}/waybar"
		else
			echo -e "  ${WARN} waybar is a plain directory (not a symlink to ${script_dir}/waybar)"
		fi
	else
		echo -e "  ${FAIL} waybar config not found (run: ln -sfn ${script_dir}/waybar ~/.config/waybar)"
		ALL_PASSED=false
	fi

	if [[ -d "${HOME}/.config/wlogout" ]] || have_native_cmd wlogout; then
		echo -e "  ${PASS} wlogout present (power menu)"
	else
		echo -e "  ${WARN} wlogout config dir not found (waybar power button needs it)"
	fi
	echo ""
}

print_summary() {
	if $ALL_PASSED; then
		echo -e "${GREEN}${BOLD}All required dependencies satisfied.${NC}"
		exit 0
	else
		echo -e "${RED}${BOLD}Some required dependencies are missing.${NC}"
		if ! $INSTALL_MODE; then
			echo -e "Run ${CYAN}$0 --install${NC} to install them automatically."
		fi
		exit 1
	fi
}

# ──────────────────── main ────────────────────

main() {
	parse_args "$@"
	OS=$(os_detect)
	print_header
	print_platform
	check_required_tools
	install_missing_required
	if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
		ALL_PASSED=false
	fi
	check_recommended_tools
	install_missing_recommended
	check_fonts
	check_config_files
	print_summary
}

main "$@"
