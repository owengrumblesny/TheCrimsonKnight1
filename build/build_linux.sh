#!/usr/bin/env bash
# Crimson Knight: export the Linux build to dist/linux/CrimsonKnight.x86_64 and copy the R.E.D. ai/ folder next to it.
#
#   build/build_linux.sh            # release build with ai/
#   build/build_linux.sh --no-ai    # game only
#   build/build_linux.sh --debug    # debug template
#
# Runs on Linux, or on Windows from Git Bash (Godot can export the Linux build from Windows).
# Godot: $GODOT, else godot / godot4 on PATH, else the WinGet install. ai/: $CK_AI_DIR, else <repo>/ai, else the main
# checkout's ai/ when run from a git worktree. On Linux, ai/ must hold the Linux binaries (see docs/BUILD.md).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo/dist/linux"
out_bin="$out_dir/CrimsonKnight.x86_64"
no_ai=0
mode="--export-release"
tpl_name="linux_release.x86_64"
for a in "$@"; do
	case "$a" in
		--no-ai) no_ai=1 ;;
		--debug) mode="--export-debug"; tpl_name="linux_debug.x86_64" ;;
		*) echo "usage: $0 [--no-ai] [--debug]" >&2; exit 2 ;;
	esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }

# ---- Godot ----
godot="${GODOT:-}"
if [ -z "$godot" ]; then
	godot="$(command -v godot || command -v godot4 || command -v Godot_v4.7.2-stable_linux.x86_64 || true)"
fi
if [ -z "$godot" ] && [ -n "${LOCALAPPDATA:-}" ]; then
	winget="$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
	[ -f "$winget" ] && godot="$winget"
fi
[ -n "$godot" ] || fail "Godot 4.7.2 not found. Set GODOT to the Godot 4.7.2 binary."

# ---- export templates ----
version="$("$godot" --version | tail -n 1 | tr -d '\r')"
tpl_version="$(echo "$version" | cut -d. -f1-4)" # 4.7.2.stable.official.abc -> 4.7.2.stable
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) tpl_root="${APPDATA}/Godot/export_templates" ;;
	Darwin) tpl_root="$HOME/Library/Application Support/Godot/export_templates" ;;
	*) tpl_root="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates" ;;
esac
tpl="$tpl_root/$tpl_version/$tpl_name"
if [ ! -f "$tpl" ]; then
	fail "Export templates for Godot $tpl_version are not installed (missing $tpl).
       Install them from the Godot editor (Editor > Manage Export Templates > Download and Install)
       or see docs/BUILD.md for the .tpz download."
fi

# ---- export ----
mkdir -p "$out_dir"
: > "$repo/dist/.gdignore" # keep Godot from scanning dist/ as project files
echo "Exporting with $godot ($version)..."
"$godot" --headless --path "$repo" "$mode" "Linux" "$out_bin" || fail "Godot export failed (exit $?). See the output above."
[ -f "$out_bin" ] || fail "Godot export produced no $out_bin."
chmod +x "$out_bin"

# ---- R.E.D. ai/ ----
if [ "$no_ai" = 0 ]; then
	ai_src="${CK_AI_DIR:-}"
	if [ -z "$ai_src" ]; then
		ai_src="$repo/ai"
		if [ ! -d "$ai_src" ]; then
			common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
			[ -n "$common" ] && ai_src="$(dirname "$common")/ai"
		fi
	fi
	if [ -f "$ai_src/llama/llama-server" ]; then
		echo "Copying R.E.D. ai/ from $ai_src..."
		rm -rf "$out_dir/ai"
		cp -a "$ai_src" "$out_dir/ai"
		chmod +x "$out_dir/ai/llama/llama-server" "$out_dir/ai/whisper/Release/whisper-server" "$out_dir/ai/piper/piper/piper" 2>/dev/null || true
	elif [ -d "$ai_src" ]; then
		echo "WARNING: $ai_src has no Linux llama-server (only Windows binaries?); skipping ai/. See docs/BUILD.md." >&2
	else
		echo "WARNING: R.E.D. ai/ folder not found (looked in '$ai_src'); the build runs with scripted R.E.D. lines only." >&2
	fi
fi

echo "Built $out_bin"
