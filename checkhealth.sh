#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-hyprland dependency check
#
# The check framework lives in scripts/ (a `git subtree` of
# github.com/QMonkey/monkey-scripts) — this file only declares WHAT to check.
# ──────────────────────────────────────────────────────────────

. "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/checkhealth.sh" || {
	echo "monkey-scripts not found — update this checkout (git pull / re-clone)," >&2
	echo "or run install.sh, which bootstraps monkey-scripts itself." >&2
	exit 1
}

# ──────────────────────── identity ────────────────────────
PROJECT=monkey-hyprland

# ──────────────────────── Hyprland version probe ────────────────────────
# Printed between the title and Platform (the original's print_header).
# Failures cannot touch REQUIRED_FAILURES here — run_required_checks resets
# the counter right after — so they are folded in by checkhealth_extra.
HYPR_VERSION_FAILED=0
print_header_extra() {
	echo -e "${BOLD}Hyprland version${NC}"
	if have_native_cmd Hyprland; then
		local out ver major minor
		out=$(Hyprland --version 2>/dev/null)
		# head -n1: the version line can carry the number twice and -o prints
		# EVERY match on it — "0.56.2\n0.56.2" then reached the arithmetic
		# compare and died with a syntax error, always failing the check
		# (observed on Hyprland 0.56.2).
		ver=$(echo "$out" | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
		if [[ -n "$ver" ]]; then
			major=${ver%%.*}
			minor=$(echo "$ver" | cut -d. -f2)
			if ((major > 0 || (major == 0 && minor >= 55))); then
				ok "Hyprland ${ver}"
			else
				fail "Hyprland ${ver} (need >= 0.55 for Lua config support)"
				HYPR_VERSION_FAILED=1
			fi
		else
			ok "Hyprland (version string unparsable: $(echo "$out" | head -1))"
		fi
		if echo "$out" | grep -qi lua; then
			ok "Lua config support built in"
		elif [[ -n "$ver" ]] && ((major > 0 || (major == 0 && minor >= 55))); then
			# 0.55+ ships the hl Lua config API in every build; the version
			# string only mentions it on some builds (observed on 0.56.2),
			# so the absence of the word is not evidence of absence.
			ok "Lua config support assumed (>= 0.55; version string does not mention it)"
		else
			warn "version string does not mention Lua — check that your build supports the hl Lua config API"
		fi
	elif have_native_cmd hyprctl; then
		warn "Hyprland binary not found, but hyprctl is available"
	else
		fail "Hyprland (not found)"
		HYPR_VERSION_FAILED=1
	fi
	echo ""
}

checkhealth_extra() {
	if [ "$HYPR_VERSION_FAILED" = 1 ]; then
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi
}

# ──────────────────────── required ────────────────────────
REQUIRED_CHECKS=(
	"@header|Required tools"
	"@note|(compositor/bar/terminal/launcher/screenshot/portals/polkit/notif/audio/wallpaper/idle/input method)"
	"hyprctl|bin|hyprctl (ships with Hyprland)"
	"waybar|bin|waybar"
	"wezterm|bin|wezterm (default terminal)"
	"wofi|bin|wofi (app launcher)"
	"grim|bin|grim (screenshot)"
	"slurp|bin|slurp (region select)"
	"wl-copy|bin|wl-clipboard (wl-copy)"
	"wlogout|bin|wlogout (power menu)"
	"wpctl|bin|wireplumber (wpctl)"
	"hyprpaper|bin|hyprpaper (wallpaper)"
	"hypridle|bin|hypridle (idle management)"
	"fcitx5|bin|fcitx5 (input method framework)"
	"xdg-desktop-portal-hyprland|anyofext:xdg-desktop-portal-hyprland|xdg-desktop-portal-hyprland (capture/sharing portal)"
	"xdg-desktop-portal-gtk|anyofext:xdg-desktop-portal-gtk|xdg-desktop-portal-gtk (file-chooser portal)"
	"hyprpolkitagent|anyofext:hyprpolkitagent|hyprpolkitagent (polkit auth agent)"
	"notif|anyofext:mako dunst|notification daemon (mako/dunst)"
)

# ──────────────────────── required install ────────────────────────
# The post-install re-probe walks the specs themselves (one "installed" /
# "still missing" line each, anyof/anyofext semantics included) instead of
# re-printing the whole section — REQUIRED_REPROBE_LIST with spec entries +
# REQUIRED_MANUAL_HINT reproduce that via the shared install_missing_required
# (monkey-scripts/lib/checks.sh). Package-name mapping lives in the shared
# lib/pkg.sh table.
REQUIRED_REPROBE_LIST=("${REQUIRED_CHECKS[@]}")
REQUIRED_MANUAL_HINT="Not in system repos — install manually: wezterm (https://wezterm.org/installation), hyprlock (https://github.com/hyprwm/hyprlock), xdg-desktop-portal-hyprland, hyprpolkitagent, hyprpaper, hypridle (on Arch all of these are in the official repo)"

# ──────────────────────── recommended ────────────────────────
RECOMMENDED_NOTE="(Missing won't block monkey-hyprland, but will degrade tray / lock / brightness / gui-dialog experience)"
RECOMMENDED_CHECKS=(
	"nm-applet|bin|nm-applet (tray network manager)"
	"hyprlock|bin|hyprlock (lock screen)"
	"brightnessctl|bin|brightnessctl"
	"pavucontrol|bin|pavucontrol"
	"nm-connection-editor|bin|nm-connection-editor"
	"hyprpicker|bin|hyprpicker (color picker)"
	"hyprsunset|bin|hyprsunset (color temperature)"
	"hyprland-dialog|bin|hyprland-guiutils (GUI helper dialogs/run/welcome)"
)

# ──────────────────────── advisory ────────────────────────
# hypr-rdp is reported here, never installed by this script: no repo carries
# it, and the installer builds it from source (install_step_post_tool). An
# RECOMMENDED_CHECKS entry would need install=none — and checks.sh prints a
# red "✗ failed to install" for those — so an advisory section is the honest
# fit. The credentials file matters as much as the binary: hyprland.lua's RDP
# section refuses to start the server without it.
# title|note|type|params|ok|incomplete|missing — the missing text carries its
# own second line (the nerd-fonts URL).
ADVISORY_SECTIONS=(
	"Fonts (optional)|(waybar icons use Nerd Font glyphs)|nerdfont||Nerd Font found||No Nerd Font detected — waybar icons may render as boxes\n    https://github.com/ryanoasis/nerd-fonts"
	"RDP server (optional)|(remote desktop on port 3389)|cmd|hypr-rdp|hypr-rdp available||hypr-rdp not installed — install.sh builds it from source\n    https://github.com/MuNeNICK/hypr-rdp#build-from-source"
	"RDP config template (optional)|(hyprland.lua renders config.toml from it)|path|$HOME/.config/hypr/rdp/config.toml.in|template present||hypr-rdp will not start until the template exists"
	"RDP credentials (optional)|(hypr-rdp will not start without it)|path|$HOME/.config/hypr-rdp/credentials|credentials present||no password file — hypr-rdp will not start until one exists\n    run install.sh, which generates one"
)

# ──────────────────────── config ────────────────────────
# src|dst|desc|mode|name|hint — hypr uses "strict" (the whole repo linked as
# ~/.config/hypr must resolve into THIS checkout); waybar accepts any symlink.
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_LINKS=(
	"$REPO_DIR|$HOME/.config/hypr|~/.config/hypr|strict||~/.config/hypr not found (run: ln -sfn $REPO_DIR ~/.config/hypr)"
	"$REPO_DIR/waybar|$HOME/.config/waybar|waybar|||waybar config not found (run: ln -sfn $REPO_DIR/waybar ~/.config/waybar)"
)
# type|params|ok|incomplete|missing
CONFIG_HINTS=(
	"any|$HOME/.config/wlogout wlogout|wlogout present (power menu)||wlogout config dir not found (waybar power button needs it)"
)

checkhealth_main "$@"
