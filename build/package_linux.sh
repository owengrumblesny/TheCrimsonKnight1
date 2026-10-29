#!/usr/bin/env bash
# Crimson Knight: package dist/linux (from build/build_linux.sh) as a .tar.gz and, on Linux with appimagetool, an AppImage.
#
#   build/package_linux.sh             # dist/CrimsonKnight-linux-x86_64.tar.gz (+ AppImage when appimagetool is found)
#   build/package_linux.sh --tar-only
#
# appimagetool: $APPIMAGETOOL, else appimagetool on PATH (see docs/BUILD.md). The AppImage bundles ai/ when
# dist/linux/ai exists (~1.3 GB): the game looks for ai/ next to its executable, which is inside the image's
# read-only mount. Build with build_linux.sh --no-ai for a small AppImage; the .tar.gz is the R.E.D.-optional route.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo/dist/linux"
bin="CrimsonKnight.x86_64"
version="${CK_VERSION:-0.9.0}"
tar_only=0
[ "${1:-}" = "--tar-only" ] && tar_only=1

[ -f "$src/$bin" ] || { echo "ERROR: $src/$bin not found. Run build/build_linux.sh first." >&2; exit 1; }

stage="$repo/dist/stage-linux"
rm -rf "$stage"
mkdir -p "$stage"

# ---- .desktop entry + icon (shared by the tarball and the AppImage) ----
write_desktop() { # $1 = Exec line
	cat <<EOF
[Desktop Entry]
Type=Application
Name=Crimson Knight
GenericName=Superhero Sandbox
Comment=Open-world superhero sandbox (Owen Enterprises)
Exec=$1
Icon=crimson-knight
Terminal=false
Categories=Game;ActionGame;
StartupWMClass=Crimson Knight: Earth-RED
EOF
}

# ---- tar.gz ----
tar_root="$stage/CrimsonKnight"
mkdir -p "$tar_root"
cp -a "$src/." "$tar_root/"
cp "$repo/build/icon/crimson_knight.png" "$tar_root/crimson-knight.png"
write_desktop "CrimsonKnight.x86_64" > "$tar_root/crimson-knight.desktop"
cat > "$tar_root/install-desktop-entry.sh" <<'EOF'
#!/bin/sh
# Adds Crimson Knight to the application menu for this user (run from the extracted folder).
dir="$(cd "$(dirname "$0")" && pwd)"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
mkdir -p "$apps" "$icons"
cp "$dir/crimson-knight.png" "$icons/crimson-knight.png"
sed "s|^Exec=.*|Exec=\"$dir/CrimsonKnight.x86_64\"|; s|^Icon=.*|Icon=crimson-knight|" "$dir/crimson-knight.desktop" > "$apps/crimson-knight.desktop"
echo "Installed $apps/crimson-knight.desktop"
EOF
chmod +x "$tar_root/$bin" "$tar_root/install-desktop-entry.sh"
tarball="$repo/dist/CrimsonKnight-$version-linux-x86_64.tar.gz"
tar -C "$stage" -czf "$tarball" CrimsonKnight
echo "Built $tarball"

[ "$tar_only" = 1 ] && { rm -rf "$stage"; exit 0; }

# ---- AppImage ----
tool="${APPIMAGETOOL:-$(command -v appimagetool || command -v appimagetool-x86_64.AppImage || true)}"
if [ "$(uname -s)" != "Linux" ] || [ -z "$tool" ]; then
	echo "Skipping AppImage (needs Linux and appimagetool; see docs/BUILD.md)."
	rm -rf "$stage"
	exit 0
fi
appdir="$stage/CrimsonKnight.AppDir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps"
# game + ai/ side by side in usr/bin, so find_ai_dir()'s "next to the executable" lookup works inside the image
cp -a "$src/." "$appdir/usr/bin/"
cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/bin/CrimsonKnight.x86_64" "$@"
EOF
chmod +x "$appdir/AppRun"
write_desktop "CrimsonKnight.x86_64" > "$appdir/crimson-knight.desktop"
cp "$appdir/crimson-knight.desktop" "$appdir/usr/share/applications/"
cp "$repo/build/icon/crimson_knight.png" "$appdir/crimson-knight.png"
cp "$repo/build/icon/crimson_knight.png" "$appdir/usr/share/icons/hicolor/256x256/apps/crimson-knight.png"
ln -sf crimson-knight.png "$appdir/.DirIcon"
appimage="$repo/dist/CrimsonKnight-$version-x86_64.AppImage"
ARCH=x86_64 "$tool" "$appdir" "$appimage"
echo "Built $appimage"
rm -rf "$stage"
