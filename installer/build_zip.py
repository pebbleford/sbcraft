"""Builds the one-step installer: installer/dist/SBCraft-Installer-<version>.zip

    python installer/build_zip.py     (after: cd mc && ./gradlew build, the add-on build, scripts/fetch_deps.sh)

The zip holds the double-click scripts and files/: the add-on, the mod, Fabric API (Apache-2.0, unchanged) and
SBCraft's own SB files. UE4SS and ReShade are not in it: install.ps1 downloads them from their official sites.
"""
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / "installer"
VERSION = next(l.split("=", 1)[1].strip() for l in (ROOT / "mc" / "gradle.properties").read_text().splitlines() if l.startswith("version="))
OUT = HERE / "dist" / f"SBCraft-Installer-{VERSION}.zip"
TOP = f"SBCraft-Installer-{VERSION}"

ENTRIES = [
    (HERE / "Install SBCraft.cmd", "Install SBCraft.cmd"),
    (HERE / "Uninstall SBCraft.cmd", "Uninstall SBCraft.cmd"),
    (HERE / "Play SBCraft.cmd", "Play SBCraft.cmd"),
    (HERE / "install.ps1", "install.ps1"),
    (HERE / "play.ps1", "play.ps1"),
    (HERE / "README.txt", "README.txt"),
    (ROOT / "LICENSE", "LICENSE.txt"),
    (ROOT / "sb" / "addon" / "build" / "SBCraft.addon64", "files/SBCraft.addon64"),
    (ROOT / "mc" / "build" / "libs" / f"sbcraft-{VERSION}.jar", f"files/sbcraft-{VERSION}.jar"),
    (ROOT / "third_party" / "dl" / "fabric-api-0.155.3+26.1.2.jar", "files/fabric-api-0.155.3+26.1.2.jar"),
    (ROOT / "sb" / "ue4ss" / "Mods" / "SBCraft" / "Scripts" / "main.lua", "files/sb/Mods/SBCraft/Scripts/main.lua"),
    (ROOT / "sb" / "lua" / "sbcraft.lua", "files/sb/Mods/SBCraft/Scripts/sbcraft.lua"),
    (ROOT / "sb" / "reshade" / "ReShade.ini", "files/sb/ReShade.ini"),
    (ROOT / "sb" / "reshade" / "ReShadePreset.ini", "files/sb/ReShadePreset.ini"),
    (ROOT / "sb" / "shaders" / "SBCraft.fx", "files/sb/reshade-shaders/Shaders/SBCraft.fx"),
]


def main() -> None:
    missing = [str(src) for src, _ in ENTRIES if not src.exists()]
    if missing:
        sys.exit("missing (build first):\n  " + "\n  ".join(missing))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for src, name in ENTRIES:
            z.write(src, f"{TOP}/{name}")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, {len(ENTRIES)} files)")


if __name__ == "__main__":
    main()
