# MODLOG — Minecraft inside FNAF: Security Breach

Journal for the SB × Minecraft passthrough. Anything not written here is lost at the next context compaction.

## Goal (2026-10-12)
Real Minecraft Java running next to FNAF: Security Breach. Its blocks, mobs and hand/HUD are drawn *inside* the
Pizzaplex: you place blocks in SB's world, and SB's walls hide blocks behind them.
Done = it works in the real game, plus a short clip.

## Recon
| thing | value |
|---|---|
| SB install | `C:\Program Files (x86)\Steam\steamapps\common\Quarters` (Steam app 747660, publisher Steel Wool) |
| SB engine | UE4 `++UE4+Release-4.27`, project `fnaf9`, exe `fnaf9\Binaries\Win64\fnaf9-Win64-Shipping.exe` |
| SB paks | one 63 GB `fnaf9-WindowsNoEditor.pak` (no IoStore) |
| SB anti-cheat | none found (single-player) |
| SB loaders | none installed |
| SB saves/config | `%LOCALAPPDATA%\fnaf9\Saved` (SaveGames, Config\WindowsNoEditor) |
| SB settings | fullscreen 1920x1080, DLSS/RTX plugins present (NGX logs) → default RHI likely D3D12 |
| Minecraft | Java, launcher in `%APPDATA%\.minecraft`; Fabric loader 0.18.4 for **1.21.11** (user's choice) and 0.19.2 for 26.1.2 |
| Java | 25.0.2 (Oracle) on PATH |
| GPU | RTX 3060, driver 591.86 |
| Compilers | **no MSVC**; CMake + Git present; winget present |
| fal MCP | not connected (401) → no generated assets; none needed for slice 1 |
| KB | no prior SB note. Relevant: GTA V passthrough example; Black Myth Wukong (UE5 D3D12: ReShade depth flat) |

## Route: frame compositing + state (the GTA V example's route)
Nearest prior project: `examples/minecraft-gta5-passthrough` (Minecraft 26.3 Fabric + GTA V ScriptHookV + ReShade add-on).

- **Minecraft side (Fabric 1.21.11 mod `sbcraft`)**: WebSocket server on 127.0.0.1; takes SB's camera (pose + FOV) and
  ground; renders from that camera with no sky/fog/clouds; exports world colour+depth and a hand/HUD overlay into
  named shared memory. Port of the example's `mc/` from 26.3 to 1.21.11.
- **SB side, two parts:**
  1. **UE4SS Lua mod** (game thread): finds the PlayerCameraManager, publishes the address of its camera cache
     (POV) via reflection (no hard-coded offsets), line-traces SB's floor/walls around Gregory → ground columns.
  2. **ReShade add-on (C++)**: reads SB's camera at present time, speaks WebSocket to Minecraft, uploads Minecraft's
     frame and runs the depth-test effect against SB's (reversed-Z) depth. Forwards mouse buttons/wheel/1-9.
- **Why not geometry transfer (SkyCraft-style)?** Drawing guest meshes inside UE4's renderer needs a native render
  hook into a shipped UE4 build; compositing reuses a working example. Trade-off: blocks get image-estimated
  lighting, not SB's real lights/shadows.
- **Why D3D11 (`-dx11`)?** The Wukong note shows ReShade getting flat depth on UE5 D3D12. UE4.27 on D3D11 is the
  well-trodden ReShade depth path. Ray tracing is lost in that mode.

## Ownership & units (details in docs/CONTRACT.md)
- SB owns movement, camera, collisions for Gregory. Minecraft follows (Steve hidden, at Gregory's feet).
- Minecraft owns: block place/break, items, mobs, the hand/HUD.
- 1 block = 1 m = 100 UE units. UE (x, y, z) [cm, left-handed Z-up] → MC (x/100, z/100 + yOff, y/100).
  mcYaw = ueYaw − 90, mcPitch = −uePitch. UE FOV is horizontal; MC's is vertical: vfov = 2·atan(tan(hfov/2)/aspect).

## First slice (per choosing-a-mashup-route.md)
1. UE4SS loads in SB, Lua logs the camera location each second (proves injection + camera read).
2. ReShade loads in SB `-dx11`; DisplayDepth shows real scene depth (not flat) → compositing is reachable.
3. Fabric mod renders from a fake host camera and exports frames (fakehost.py check).
4. Real: a gold block placed 3 m in front of Gregory stays glued to the floor while walking and is hidden by a wall.

## Needs (asked the user)
- VS 2022 Build Tools (C++ x64) via winget — for the ReShade add-on.
- UE4SS (RE-UE4SS release) into SB's Win64 folder; ReShade 6.x add-on build into SB's Win64 folder.
- Fabric API for 1.21.11; a separate launcher profile + game dir (`C:\fnafsbxmc\mcgame`) so the mod can't touch real worlds.
- Backups first: `um backup create "%LOCALAPPDATA%\fnaf9\Saved" --name sb-saves`.

## Log
- 2026-10-12: recon done, route chosen (above).
- 2026-10-12: user picked "Minecraft inside SB" + switched MC to **26.1.2** (closest to the 26.3 example).
  Installed: VS 2022 Build Tools (MSVC 14.44.35207) via winget; uv venv `.venv` (py3.12, websockets/numpy/pillow).
  Downloads in `third_party/dl/`: UE4SS v3.0.1 (sha256 4b47d4bc…), ReShade 6.8.0 Addon (afe4c8f1…), Fabric API 0.155.3+26.1.2.
  Backup: `~/.universal-modder/backups/sb-saves/20261012-184127.zip` (restore: `um backup restore sb-saves`).
- MC mod port 26.3 → 26.1.2 (`mc/`, mod id `sbcraft`, package `dev.sbcraft`), differences found:
  1. `com.mojang.renderpearl.*` (26.3) is `com.mojang.blaze3d.{buffers,systems,textures,opengl}` in 26.1.2.
  2. 26.1.2 is GLFW, not SDL: `GLFW.glfwRestoreWindow/glfwSetWindowSize`.
  3. `minecraft.gui.screen()` → `minecraft.screen`; `gui.hud.toggle()` → `options.hideGui`; `mainCamera()` → `getMainCamera()`;
     `GpuDevice.isZZeroToOne()` directly; `clearColorTexture(tex, int argb)`; map via `CommandEncoder.mapBuffer(buf, r, w)`.
  4. `GameRenderer.mainRenderTarget` field gone → `Minecraft.getMainRenderTarget()`. Level call is
     `LevelRenderer.renderLevel(..., Vector4f, boolean sky (arg 7), ChunkSectionsToRender)`.
  5. **Depth readback**: 26.1.2 `GlCommandEncoder.copyTextureToBuffer` always attaches the source as COLOR_ATTACHMENT0 →
     GL_INVALID_FRAMEBUFFER_OPERATION (1286) on the depth texture. Fix: `DepthReadback` (own FBO, depth attachment, PBO).
  6. **Depth is cleared before the hand** in 26.1.2 (`clearDepthTexture(main, 1.0)` right before `renderItemInHand`) →
     capture right AFTER `LevelRenderer.renderLevel`.
  7. 26.1.2 is **standard Z** (cleared to 1.0), 26.3 is reversed → frame flags = zZeroToOne | bottom-up (no 4).
- Oracle: `host/fakehost.py 10 out\fakehost2 fp` against the dev client → `out/fakehost2/comp_*.png`: blocks sit on the
  fake ground, the fake host's red pillar hides MC planks behind it, hand/HUD overlay on top. Depth 0.984..1.0. PASS (synthetic).
- 2026-10-12 19:00–20:00 **SB side live.** UE4SS v3.0.1 + Lua loader (hot-reloads `sb/lua/sbcraft.lua`), ReShade 6.8.0 as
  `dxgi.dll` + `SBCraft.addon64`, SB launched `steam -applaunch 747660 -dx11 -windowed -ResX=1920 -ResY=1080`.
  Facts: PlayerCameraManager.CameraCachePrivate @6896, CameraCacheEntry {Timestamp@0, POV@16} (property is `Timestamp`,
  not `TimeStamp`); POV.Location @6912 / Rotation @6924 / FOV @6936; RelativeLocation @284 on the root; Gregory pawn class
  `Gregory_C` in `MAP_TheWorld`, capsule half height 60, camera ~46 cm above the capsule centre, FOV 75 (horizontal).
  Menus/splash use `DefaultPawn`.
  Gotchas:
  1. **Render-thread hang (GameThread timed out waiting for RenderThread, 120 s)** on the splash screen with the full
     SBCraft.fx (re-projection + contact shadows + glow + edge softening) active. Bisected: no upload → fine; upload,
     effect inactive → fine; reduced shader (those four off) → fine through splash → gameplay. Guard added: composite only
     when pawn != DefaultPawn. Full shader not yet re-enabled (`sb/shaders/SBCraft.full.fx`).
  2. ReShade's `is_mouse_button_pressed` never fires in SB (Unreal reads the mouse as raw input) → poll
     `GetAsyncKeyState` while SB's window has the focus.
  3. Only floors existed in Minecraft → nothing to place against when looking ahead, arrows lost in the void. Added
     wall scan: horizontal line traces at 0.5/1.5/2.5 m in ±x/±y across the 25×25 area, each surface marks the cell
     behind it (`w x y z` lines) → ~1800 wall barrier cells. Traces skip `Character` actors (animatronics).
  4. `LineTraceSingleForObjects` with an ObjectTypes Lua table fails inside UE4SS's param conversion → use
     `LineTraceSingle` (Visibility) and skip characters.
  5. Barrier markers: holding/picking a barrier shows them → no pick-block forwarding; BLOCK_MARKER particles cancelled.
  6. `printf` mangles `\r` in ini paths → write ReShade.ini from Python.
  7. Lua locals must be declared before the function using them (WALL_HEIGHTS nil → "attempt to index a nil value").
  Oracle (real game, user playing): forwarded `use down/up` in ReShade.log; TNT placed on SB's floor, outline on the floor
  (`out/sb_shot4.png`); bow fires (proj events).
- 2026-10-12 20:00–20:20 **collision, pearls, sword, TNT, look.**
  - Block collision: add-on keeps MC's solid blocks (`blocks` events + `blocksync` on level) → `run/sb_blocks.txt`
    (Unreal centres); Lua spawns `/Script/Engine.TriggerBox` per block via `World:SpawnActor`, then
    `SetBoxExtent(50)`, `SetCollisionProfileName("BlockAll")`, `SetCollisionEnabled(3)`. Probe trace hit it at 151 cm.
    `SetCanEverAffectNavigation` is not callable from Lua (throws). Our boxes are skipped by the floor/wall scan.
  - Ender pearls: MC `pteleport` → `run/sb_teleport.txt` → `Gregory:K2_SetActorLocation(feet + half, false, {}, true)`.
  - SB animatronics (recon via `chars` command): `AISeeker_C` (MontyStandard_C, Endo_C, …), `StaffBotBase_C`,
    `Freddy_C`, all with `CanBeStunned()` (returns bool), `StunForDuration(float)`, `Stun()`, `Unstun()`. UFunction
    params can't be listed from UE4SS Lua (ForEachProperty on a UFunction throws). `IsStunned` needs an out param.
  - Sword: MC `melee` → `run/sb_actions.txt` (`id melee`) → stun seekers within 3.5 m and ~70° of view for 4 s.
  - TNT/creeper: MC `explosion` → `id explode x y z r` → stun seekers within 2r for 8 s; hide + uncollide
    StaticMeshComponents within r (5248 in the level, sweep ≈110 ms) except: owners Door/Gate/Save/Elevator/Lift/Vent/
    Pickup/Interact/characters/ours, half-extent > 5 m, **anything reaching > 40 cm below the floor** (hallway modules
    `MOD_Hallway01` include their own floor), thin slabs at the blast's feet. `restore` command brings them all back.
    The add-on clears MC's barriers and rebuilds them from the next ground pass, so blown walls stop blocking in MC.
  - Look: relight floor 0.06 (was 0.42 — blocks glowed in SB's dark), reference 0.3, light blur mip 5.5 (3.2 imprinted
    SB's light streaks on blocks), tint 0.35, grade 0.4; re-projection, edge softening, contact shadows back on, glow off.
    No hang in gameplay → the splash hang was the loading-screen present (guarded by pawn != DefaultPawn).
  - Gotchas: Lua 5.4 for-loop variables are const; a GetActorBounds(bOnlyColliding=true) on mesh-less actors gives 0.
- 2026-10-13 **Steam one-click launcher.** `launcher/SBCraft.ps1` (starts `gradlew runClient` unless the link port 25599
  is open, waits for it, `steam -applaunch 747660 -dx11 -windowed -ResX=1920 -ResY=1080`, waits for
  fnaf9-Win64-Shipping to exit, closes the Minecraft it started by exact PID) behind `launcher/SBCraft.exe` (hidden
  PowerShell, waits so Steam shows "playing"). `launcher/add_to_steam.ps1` writes a non-Steam shortcut into
  `userdata/<newest>/config/shortcuts.vdf` (binary VDF, appid = crc32('"exe"' + name) | 0x80000000) with Steam shut
  down (`steam -shutdown`), backup `shortcuts.vdf.sbcraft-backup`. Tested end to end: MC link up in 20 s, SB up 4 s
  later, add-on + Lua on the new default link folder `Win64\Mods\SBCraft\link`; on SB exit Minecraft closed.
  Gotchas: Lua in SB can't open files through a directory junction ("No such file or directory") → link folder lives
  in the mod folder; PowerShell hex literals ≥ 0x80000000 are negative Int32; under Git Bash, `ProgramFiles(x86)` is
  dropped from cmd's environment and `NoDefaultCurrentDirectoryInExePath` is set (use `.\vswhere.exe`).
