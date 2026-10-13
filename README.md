# SBCraft: Minecraft inside FNAF: Security Breach

Real Minecraft Java runs next to *Five Nights at Freddy's: Security Breach*, and its picture is blended into SB's.
You walk around the Pizzaplex as Gregory, with Minecraft's hand and hotbar, and build in it.

- **Build in the Pizzaplex.** Place and break Minecraft blocks on SB's floors and walls. Blocks are depth-tested
  against SB, so SB's walls hide them, and they're lit to match SB's darkness.
- **Blocks are solid in SB.** Every placed block becomes an invisible blocking box in SB. Gregory can't walk through
  it, and animatronics run into it and lose sight of you behind it.
- **Diamond sword stuns animatronics** (SB's own stun, 4 s) when you hit one within about 3.5 m.
- **TNT and creepers** stun animatronics in the blast (8 s) and blow away SB's props, vents, lamps and wall panels.
  Floors, doors, gates, save stations and elevators are never touched.
- **Ender pearls** teleport Gregory to where they land.
- **Bow, crossbow, fireworks:** arrows stick in SB's walls (walls and floors are invisible barriers in Minecraft).

Built and tested on Windows 11 in October 2026 with SB on Steam (Unreal 4.27, D3D11 mode), Minecraft Java 26.1.2
with Fabric Loader 0.19.2 and Fabric API 0.155.3, UE4SS 3.0.1 and ReShade 6.8.0. **Single-player only.**

## How it works

```
Security Breach (UE4.27, -dx11)                                Minecraft 26.1.2 + Fabric (mc/)
  UE4SS Lua mod (sb/lua/sbcraft.lua), game thread                dev.sbcraft
    finds the camera by reflection, line-traces floors/walls       HostLink: WebSocket 127.0.0.1:25599
    spawns blocking boxes, stuns, explodes, teleports              FrameExporter: colour + depth + hand/HUD
          | text files in the link folder                                         -> shared memory
  ReShade add-on (sb/addon, SBCraft.addon64), at present time
    reads SB's camera from memory  --- WebSocket cam/ground/input --->  Minecraft renders from SB's camera
    composites Minecraft's frame   <--- shared memory frames -------
    (SBCraft.fx: depth test vs SB's reversed-Z depth, relight, re-projection)
```

1 Minecraft block = 1 m = 100 Unreal units. Unreal (x, y, z) → Minecraft (x/100, z/100 + yOffset, y/100). The bridge
contract (ownership, units, channels, lifecycle) is in [docs/CONTRACT.md](docs/CONTRACT.md). Everything learned
building it, including the dead ends, is in [MODLOG.md](MODLOG.md).

## Download

**Easiest:** download **`SBCraft-Installer-<version>.zip`** from the
**[latest release](https://github.com/pebbleford/sbcraft/releases/latest)** and extract it. Close SB and the Minecraft
Launcher, then double-click `Install SBCraft.cmd`.

- It finds Security Breach on any drive, or asks for its folder.
- It downloads UE4SS and ReShade from their official sites and installs SBCraft into SB.
- It sets up Fabric and an **SBCraft** installation in the Minecraft Launcher.
- It puts **Play SBCraft** on your desktop. That shortcut opens the Minecraft Launcher (press Play on SBCraft), then
  starts SB in D3D11 mode once Minecraft is ready.

No Git, Java or Visual Studio needed.

The same release also has the individual files, rebuilt automatically on every update:

- `sbcraft-<version>.jar`: the mod
- `fabric-api-0.155.3+26.1.2.jar`: Fabric API, which the mod needs
- `SBCraft-<version>.mrpack`: both in a Modrinth modpack
- `SBCraft.addon64`: the prebuilt SB add-on

With these you can skip building (steps 2 and 4 below, and Visual Studio). For the add-on, put `SBCraft.addon64`
into `sb/addon/build/` before running `sb/install.sh`.

## What you need

- **Windows 10/11.**
- **FNAF: Security Breach on Steam.** It runs in D3D11 mode (`-dx11`), which turns off ray tracing.
- **Minecraft Java Edition** with the official launcher.
- **JDK 25**, for example [Temurin 25](https://adoptium.net/) or Oracle JDK 25.
- **Visual Studio 2022 Build Tools** with "Desktop development with C++":
  ```bash
  winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  ```
- **Git for Windows**, which provides the Git Bash used by the scripts.

## Install

All commands run in **Git Bash** from the repository folder.

### 1. Get the code and the third-party pieces

```bash
git clone https://github.com/pebbleford/sbcraft.git
```

```bash
cd sbcraft && bash scripts/fetch_deps.sh
```

`fetch_deps.sh` downloads UE4SS v3.0.1, ReShade 6.8.0 (add-on build), its headers and shader includes, and Fabric API
into `third_party/`, checking the SHA-256 of the pinned files. None of those are redistributed in this repository.

### 2. Build the Minecraft mod

```bash
cd mc && ./gradlew build
```

This produces `mc/build/libs/sbcraft-0.1.0.jar`.

### 3. Set up a separate Minecraft profile

The mod creates its own empty creative world called `passthrough` and opens it automatically. It also changes some
options (no clouds, no view bobbing, keeps running when unfocused). **Give it its own game folder so your normal worlds
and settings are never touched.**

1. Run the [Fabric installer](https://fabricmc.net/use/installer/) and install **Fabric Loader 0.19.2 or newer for
   Minecraft 26.1.2**.
2. In the Minecraft launcher, go to **Installations → New installation**:
   - **Version:** `fabric-loader-0.19.x-26.1.2`
   - **Game directory:** a new folder, for example `C:\SBCraft\minecraft`
3. Create `C:\SBCraft\minecraft\mods` and copy two files into it:
   - `third_party/dl/fabric-api-0.155.3+26.1.2.jar`
   - `mc/build/libs/sbcraft-0.1.0.jar`

Instead of steps 1–3, you can run a development client straight from the repository (offline account, its own game
folder in `mc/run`):

```bash
cd mc && ./gradlew runClient
```

### 4. Build the SB add-on

```bash
bash sb/addon/build.sh
```

This produces `sb/addon/build/SBCraft.addon64`.

### 5. Install into Security Breach

Back up your saves first: copy `%LOCALAPPDATA%\fnaf9\Saved\SaveGames` somewhere safe. Then run:

```bash
bash sb/install.sh
```

The script copies these into `...\steamapps\common\Quarters\fnaf9\Binaries\Win64` (`Quarters` is SB's install folder
name):

- UE4SS (`dwmapi.dll`, `UE4SS.dll`, `UE4SS-settings.ini`, `Mods\`) and the SBCraft Lua mod
- ReShade as `dxgi.dll`, `SBCraft.addon64`, `ReShade.ini`, `ReShadePreset.ini` and `reshade-shaders\`

It refuses to overwrite files it didn't install (`FORCE=1` overrides) and records everything it added in
`.sbcraft_manifest`.

The script finds SB in any of your Steam libraries, on any drive, and prints where it installs. If it can't find SB,
point it at the `Quarters` folder yourself:

```bash
SB_DIR="D:\SteamLibrary\steamapps\common\Quarters" bash sb/install.sh
```

### 6. Set SB's launch options

In Steam, right-click **FNAF: Security Breach → Properties → Launch options** and enter:

```
-dx11 -windowed -ResX=1920 -ResY=1080
```

`-dx11` is required, because the depth compositing reads SB's D3D11 depth buffer. Windowed mode is recommended.

### 7. (Optional) One-click Steam entry

Build the launcher, then add it to your Steam library as a non-Steam game:

```bash
cmd //c "$(cygpath -w launcher/build.bat)"
```

```bash
pwsh -NoProfile -File launcher/add_to_steam.ps1
```

`add_to_steam.ps1` closes Steam for a few seconds, which also closes any game you're running. It backs up your
`shortcuts.vdf`, adds an **SBCraft** entry pointing at `launcher\SBCraft.exe`, and reopens Steam. You can also add
`SBCraft.exe` by hand: **Games → Add a Non-Steam Game to My Library → Browse**.

Pressing **Play** on SBCraft does the following:

1. Starts the Minecraft dev client (`gradlew runClient`), unless one is already running, and waits for its link.
2. Starts Security Breach through Steam with `-dx11 -windowed -ResX=1920 -ResY=1080`.
3. Closes that Minecraft when you quit SB.

It logs to `run\launcher.log`. The first launch builds the mod, which takes a minute or two.

## Play

1. Start Minecraft with the SBCraft profile and leave its window open. It renders slowly when minimized.
2. Start SB from Steam and load your save.
3. Once you're walking around as Gregory, Minecraft's hand and hotbar appear in SB.
   - Minecraft and SB can be started in either order; the link reconnects on its own.
   - Compositing pauses on menus and loading screens.

| Key (with SB focused) | Action |
|---|---|
| Left mouse | Minecraft attack: break blocks, swing the sword (stuns animatronics) |
| Right mouse | Minecraft use: place blocks, light TNT, shoot (hold for bow), throw pearls |
| Mouse wheel, 1–9 | Minecraft hotbar |
| F7 | Passthrough on/off |
| F8 | Re-level Minecraft's floor to where you stand (after stairs/elevators, or if a door left an invisible wall) |

Starting hotbar: ender pearls, diamond sword, crossbow, bow, TNT, flint and steel, creeper eggs, grass, fireworks.
Give yourself anything else from Minecraft's chat (`/give @s minecraft:oak_planks 64`).

TNT can blow away a lot. To bring back every piece removed by blasts this session, write `restore` into
`sb_cmd.txt` in the link folder (`...\Win64\Mods\SBCraft\link\`).

## Uninstall

```bash
bash sb/install.sh --remove
```

This deletes exactly the files listed in the manifest, then the link folder. To restore your saves, copy your backup
back.

## Known issues

- Left/right click also do whatever SB itself does with them.
- SB's collision is approximated on a 1 m grid, so blocks placed on walls can sit up to a block off SB's surface. A
  door that opens leaves its invisible Minecraft wall until you press F8.
- Animatronics stopped by a block push against it instead of pathing around it (SB's navigation doesn't update).
- Minecraft's hand and HUD are drawn at full brightness.
- Blocks get image-estimated lighting from SB's picture, not SB's real lights and shadows.
- An early build froze SB's splash screen while compositing during the loading screen. Compositing now only runs in
  gameplay, and it hasn't recurred, but report it if SB ever stops responding.

## Safety

- SB is single-player with no anti-cheat. Don't use this with anything online.
- The WebSocket link listens on `127.0.0.1:25599` only, with no authentication. Close Minecraft when you're done.
- No game files from Security Breach or Minecraft are included. Everything game-side is read at runtime from your own
  installs.

## Credits

- Built with **Claude Code**, using the [universal-modder](https://github.com/rehan-remade/universal-modder) toolkit.
  The Minecraft mod, compositor, shader and host test tools are adapted from its MIT-licensed
  `examples/minecraft-gta5-passthrough` (Minecraft × GTA V) by Rehan and contributors.
- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for Unreal scripting.
- [ReShade](https://reshade.me) and its add-on API by crosire, plus `ReShade.fxh` and `DisplayDepth.fx` from
  [crosire/reshade-shaders](https://github.com/crosire/reshade-shaders).
- [Fabric](https://fabricmc.net): Fabric Loader, Fabric API, Loom.
- [Java-WebSocket](https://github.com/TooTallNate/Java-WebSocket) by TooTallNate, bundled in the mod.
- *Five Nights at Freddy's: Security Breach* belongs to Steel Wool Studios and Scott Cawthon; Minecraft belongs to
  Mojang Studios and Microsoft. This is an unofficial fan project, not affiliated with either.

## License

MIT, see [LICENSE](LICENSE).
