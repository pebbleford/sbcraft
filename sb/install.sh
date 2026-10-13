#!/bin/bash
# Installs the SB side of SBCraft into Security Breach's Win64 folder, or removes it again.
#   sb/install.sh            install UE4SS v3.0.1 + the SBCraft Lua mod (+ ReShade and the add-on once built)
#   sb/install.sh --remove   delete exactly the files listed in the manifest it wrote
#   sb/install.sh "D:\SteamLibrary\steamapps\common\Quarters"   use this SB install (any folder in or around it works:
#                            the Quarters folder, fnaf9, Win64, or the exe itself); also SB_DIR=... for the same
# Without a path, SB is searched for in every Steam library, Epic Games installs, and common folders on every drive.
# It refuses to overwrite a file it didn't install (FORCE=1 overrides). Files come from third_party/ (downloaded,
# never committed) and sb/ (ours).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

# Steam's own folder (registry), then every library listed in its libraryfolders.vdf
steam_libraries() {
	local steam
	steam=$(reg query 'HKCU\Software\Valve\Steam' //v SteamPath 2>/dev/null | sed -n 's/.*SteamPath[[:space:]]*REG_SZ[[:space:]]*//p' | tr -d '\r')
	[ -n "$steam" ] || steam="C:/Program Files (x86)/Steam"
	echo "$steam"
	local vdf="$steam/steamapps/libraryfolders.vdf"
	[ -f "$vdf" ] && sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$vdf" | sed 's/\\\\/\\/g' | tr -d '\r'
}
EXE_REL="fnaf9/Binaries/Win64/fnaf9-Win64-Shipping.exe"

# The SB root (the folder that contains fnaf9) for any path in or around an install, or nothing.
resolve_sb() {
	local p
	p=$(cygpath -u "$1" 2>/dev/null) || return 1
	p=${p%/}
	[ -f "$p" ] && p=$(dirname "$p")
	[ -d "$p" ] || return 1
	local up=$p i
	for i in 1 2 3 4 5; do # the path is inside the install: walk up
		[ -f "$up/$EXE_REL" ] && { echo "$up"; return 0; }
		[ "$up" = "/" ] || [ "$up" = "$(dirname "$up")" ] && break
		up=$(dirname "$up")
	done
	local d # the path is above the install (steamapps, common, a library): look a few levels down
	for d in "$p"/* "$p"/*/* "$p"/*/*/* "$p"/*/*/*/*; do
		[ -f "$d/$EXE_REL" ] && { echo "$d"; return 0; }
	done 2>/dev/null
	return 1
}

# Every place SB could be, best guesses first.
sb_candidates() {
	steam_libraries | while IFS= read -r lib; do [ -n "$lib" ] && echo "$lib/steamapps/common/Quarters"; done
	# Epic Games: each installed game has a manifest with its InstallLocation
	local m
	for m in /c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests/*.item; do
		[ -f "$m" ] && sed -n 's/.*"InstallLocation"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$m" | sed 's/\\\\/\\/g'
	done
	local drive
	for drive in /?; do
		for d in "$drive/SteamLibrary/steamapps/common/Quarters" "$drive/Steam/steamapps/common/Quarters" \
			"$drive/Program Files (x86)/Steam/steamapps/common/Quarters" "$drive/Games/Steam/steamapps/common/Quarters" \
			"$drive/Program Files/Epic Games" "$drive/Epic Games" "$drive/Games"; do
			echo "$d"
		done
	done
}

GIVEN=${SB_DIR:-}
[ -n "${1:-}" ] && [ "${1:-}" != "--remove" ] && GIVEN=$1
[ "${1:-}" = "--remove" ] && [ -n "${2:-}" ] && GIVEN=$2
SB_DIR=
if [ -n "$GIVEN" ]; then
	SB_DIR=$(resolve_sb "$GIVEN") || {
		echo "Couldn't find Security Breach in or around: $GIVEN"
		echo "Give the folder that contains 'fnaf9' (Steam: right-click the game > Manage > Browse local files)."
		exit 1
	}
else
	while IFS= read -r cand; do
		[ -n "$cand" ] || continue
		if found=$(resolve_sb "$cand"); then SB_DIR=$found; break; fi
	done < <(sb_candidates)
	[ -n "$SB_DIR" ] || {
		echo "Couldn't find Security Breach automatically. Run this with the game's folder, for example:"
		echo "  bash sb/install.sh \"D:\\SteamLibrary\\steamapps\\common\\Quarters\""
		echo "(Steam: right-click the game > Manage > Browse local files shows that folder.)"
		exit 1
	}
fi
WIN64="$SB_DIR/fnaf9/Binaries/Win64"
MANIFEST="$WIN64/.sbcraft_manifest"
[ -f "$WIN64/fnaf9-Win64-Shipping.exe" ] || { echo "no SB at $WIN64 (set SB_DIR to the folder that contains fnaf9)"; exit 1; }
echo "Security Breach: $SB_DIR"

if [ "${1:-}" = "--remove" ]; then
	[ -f "$MANIFEST" ] || { echo "nothing installed (no manifest)"; exit 0; }
	while IFS= read -r rel; do
		[ -f "$WIN64/$rel" ] && rm -f "$WIN64/$rel" && echo "removed $rel"
	done < "$MANIFEST"
	# then the folders we created, deepest first, only if empty
	awk '{ print length($0) "\t" $0 }' "$MANIFEST" | sort -rn | cut -f2- | while IFS= read -r rel; do
		[ -d "$WIN64/$rel" ] && rmdir "$WIN64/$rel" 2>/dev/null && echo "removed $rel/"
	done
	rm -f "$MANIFEST"
	rm -rf "$WIN64/Mods/SBCraft/link" # the link folder's state files
	rmdir "$WIN64/Mods/SBCraft" "$WIN64/Mods" 2>/dev/null || true
	echo "SBCraft removed from $WIN64"
	exit 0
fi

touch "$MANIFEST"
put() { # put <source> <relative destination>
	local src=$1 rel=$2 dst="$WIN64/$2"
	if [ -e "$dst" ] && ! grep -qxF "$rel" "$MANIFEST" && [ -z "${FORCE:-}" ]; then
		echo "refusing to replace $rel (not ours; FORCE=1 to override)"; exit 1
	fi
	mkdir -p "$(dirname "$dst")"
	local d=$(dirname "$rel")
	while [ "$d" != "." ]; do grep -qxF "$d" "$MANIFEST" || [ -e "$WIN64/$d/.keep_sbcraft_never" ] || echo "$d" >> "$MANIFEST.dirs"; d=$(dirname "$d"); done
	cp "$src" "$dst"
	grep -qxF "$rel" "$MANIFEST" || echo "$rel" >> "$MANIFEST"
	echo "installed $rel"
}

UE="$ROOT/third_party/ue4ss"
[ -f "$UE/UE4SS.dll" ] || { echo "extract UE4SS_v3.0.1.zip into third_party/ue4ss first"; exit 1; }
put "$UE/dwmapi.dll" dwmapi.dll
put "$UE/UE4SS.dll" UE4SS.dll
# settings: no GUI console window (logs go to UE4SS.log), everything else stock
sed -e 's/^GuiConsoleEnabled = 1/GuiConsoleEnabled = 0/' "$UE/UE4SS-settings.ini" > "$ROOT/third_party/UE4SS-settings.sbcraft.ini"
put "$ROOT/third_party/UE4SS-settings.sbcraft.ini" UE4SS-settings.ini
(cd "$UE" && find Mods -type f) | while IFS= read -r f; do
	[ "$f" = "Mods/mods.txt" ] && continue
	put "$UE/$f" "$f"
done
for f in $(cd "$HERE/ue4ss" && find Mods -type f); do put "$HERE/ue4ss/$f" "$f"; done
# the logic the loader runs (it prefers a dev checkout at SBCRAFT_DEV_LOGIC when there is one)
put "$HERE/lua/sbcraft.lua" Mods/SBCraft/Scripts/sbcraft.lua
# mods.txt: the stock list plus SBCraft (before the Keybinds line, which must stay last)
awk '/^; Built-in keybinds/ && !done { print "SBCraft : 1\n"; done=1 } { print }' "$UE/Mods/mods.txt" > "$ROOT/third_party/mods.sbcraft.txt"
put "$ROOT/third_party/mods.sbcraft.txt" Mods/mods.txt

# ReShade + the compositor add-on, once built (SB must run with -dx11 for its depth to be readable)
if [ -f "$ROOT/sb/addon/build/SBCraft.addon64" ]; then
	put "$ROOT/third_party/reshade/ReShade64.dll" dxgi.dll
	put "$ROOT/sb/addon/build/SBCraft.addon64" SBCraft.addon64
	put "$HERE/reshade/ReShade.ini" ReShade.ini
	put "$HERE/reshade/ReShadePreset.ini" ReShadePreset.ini
	put "$HERE/shaders/SBCraft.fx" reshade-shaders/Shaders/SBCraft.fx
	for f in ReShade.fxh ReShadeUI.fxh DisplayDepth.fx; do put "$ROOT/third_party/shaders/$f" "reshade-shaders/Shaders/$f"; done
fi
# directories we created go last in the manifest (removed after their files, if empty)
if [ -f "$MANIFEST.dirs" ]; then sort -u "$MANIFEST.dirs" | sort -r >> "$MANIFEST"; rm -f "$MANIFEST.dirs"; fi
awk '!seen[$0]++' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
mkdir -p "$WIN64/Mods/SBCraft/link" # the folder the add-on and the Lua mod share (link_dir.txt there overrides it)
echo "done; manifest: $MANIFEST"
