"""Builds the SBCraft Modrinth modpack (modrinth/dist/SBCraft-<version>.mrpack) — the Minecraft half of SBCraft.

    python modrinth/build_mrpack.py            (build the mod first: cd mc && ./gradlew build)

The pack (Modrinth format v1):
  modrinth.index.json   Minecraft 26.1.2 + Fabric Loader, Fabric API fetched from Modrinth's CDN (hash-checked)
  overrides/mods/       the sbcraft mod itself (not on Modrinth)
Standard library only. Fabric API is downloaded once into third_party/dl to hash it.
"""
import hashlib
import json
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.1.0"
MINECRAFT = "26.1.2"
FABRIC_LOADER = "0.19.2"
MOD_JAR = ROOT / "mc" / "build" / "libs" / f"sbcraft-{VERSION}.jar"
FABRIC_API = {
    "file": "fabric-api-0.155.3+26.1.2.jar",
    "url": "https://cdn.modrinth.com/data/P7dR8mSH/versions/3dM0X6ou/fabric-api-0.155.3%2B26.1.2.jar",
    "sha1": "16c30dfcceaed1ac3b6ac84cbd348a906dc5093e",
}
OUT = ROOT / "modrinth" / "dist" / f"SBCraft-{VERSION}.mrpack"


def hashes(data: bytes) -> dict:
    return {"sha1": hashlib.sha1(data).hexdigest(), "sha512": hashlib.sha512(data).hexdigest()}


def fabric_api_bytes() -> bytes:
    local = ROOT / "third_party" / "dl" / FABRIC_API["file"]
    if not local.exists():
        local.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(FABRIC_API["url"], headers={"User-Agent": "sbcraft-build/0.1 (github.com/pebbleford/sbcraft)"})
        local.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    data = local.read_bytes()
    got = hashlib.sha1(data).hexdigest()
    if got != FABRIC_API["sha1"]:
        sys.exit(f"{local}: sha1 {got}, expected {FABRIC_API['sha1']} (delete it and retry)")
    return data


def main() -> None:
    if not MOD_JAR.exists():
        sys.exit(f"build the mod first (cd mc && ./gradlew build): {MOD_JAR} is missing")
    api = fabric_api_bytes()
    index = {
        "formatVersion": 1,
        "game": "minecraft",
        "versionId": VERSION,
        "name": "SBCraft",
        "summary": "Minecraft inside FNAF: Security Breach (the Minecraft half of the SBCraft passthrough mod).",
        "files": [
            {
                "path": f"mods/{FABRIC_API['file']}",
                "hashes": hashes(api),
                "env": {"client": "required", "server": "unsupported"},
                "downloads": [FABRIC_API["url"]],
                "fileSize": len(api),
            }
        ],
        "dependencies": {"minecraft": MINECRAFT, "fabric-loader": FABRIC_LOADER},
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("modrinth.index.json", json.dumps(index, indent=2))
        z.write(MOD_JAR, f"overrides/mods/{MOD_JAR.name}")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
    print(f"  minecraft {MINECRAFT}, fabric-loader {FABRIC_LOADER}")
    print(f"  mods/{FABRIC_API['file']} from Modrinth (sha512 {index['files'][0]['hashes']['sha512'][:16]}...)")
    print(f"  overrides/mods/{MOD_JAR.name} ({MOD_JAR.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
