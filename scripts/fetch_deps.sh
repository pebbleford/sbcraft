#!/bin/bash
# Downloads what SBCraft needs but may not redistribute, into third_party/ (git-ignored), from the original sources,
# and checks the pinned files' SHA-256:
#   third_party/ue4ss/            RE-UE4SS v3.0.1 (github.com/UE4SS-RE/RE-UE4SS)
#   third_party/reshade/          ReShade64.dll 6.8.0 with add-on support (reshade.me) + its add-on API headers
#   third_party/shaders/          ReShade.fxh, ReShadeUI.fxh, DisplayDepth.fx (crosire/reshade-shaders, slim branch)
#   third_party/dl/               the downloads themselves, plus Fabric API 0.155.3+26.1.2 (Modrinth)
# Run from Git Bash: bash scripts/fetch_deps.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TP="$ROOT/third_party"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
mkdir -p "$TP/dl" "$TP/ue4ss" "$TP/reshade/include" "$TP/shaders"

fetch() { # fetch <url> <file> <sha256 or ->
	local url=$1 out="$TP/dl/$2" sum=$3
	[ -f "$out" ] || curl -fsSL -A "$UA" -o "$out" "$url"
	if [ "$sum" != "-" ]; then
		echo "$sum *$out" | sha256sum -c --quiet - || { echo "checksum mismatch: $out (delete it and retry)"; exit 1; }
	fi
	echo "ok $2"
}

fetch https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip \
	UE4SS_v3.0.1.zip 4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec
fetch https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe \
	ReShade_Setup_6.8.0_Addon.exe afe4c8f13048306307983b8b3d41d5bf00a86820440b0e57dea10950e1176445
fetch "https://cdn.modrinth.com/data/P7dR8mSH/versions/3dM0X6ou/fabric-api-0.155.3%2B26.1.2.jar" \
	fabric-api-0.155.3+26.1.2.jar 7fe7bea3dbb7b2e9ff998ab583130cd62fab22ab8a5229656ff14b2e648c91dd

unzip -qo "$TP/dl/UE4SS_v3.0.1.zip" -d "$TP/ue4ss"
# the ReShade setup carries its DLLs as an appended zip (unzip warns about the exe in front of it)
unzip -qo "$TP/dl/ReShade_Setup_6.8.0_Addon.exe" ReShade64.dll -d "$TP/reshade" 2>/dev/null || true
[ -f "$TP/reshade/ReShade64.dll" ] || { echo "could not extract ReShade64.dll"; exit 1; }

for f in reshade.hpp reshade_api.hpp reshade_api_device.hpp reshade_api_pipeline.hpp reshade_api_resource.hpp \
	reshade_api_format.hpp reshade_events.hpp reshade_overlay.hpp; do
	curl -fsSL "https://raw.githubusercontent.com/crosire/reshade/v6.8.0/include/$f" -o "$TP/reshade/include/$f"
done
for f in ReShade.fxh ReShadeUI.fxh DisplayDepth.fx; do
	curl -fsSL "https://raw.githubusercontent.com/crosire/reshade-shaders/slim/Shaders/$f" -o "$TP/shaders/$f"
done
echo "third_party ready"
