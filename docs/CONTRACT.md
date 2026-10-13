# SBCraft bridge contract (SB × Minecraft 26.1.2)

## Who owns what
| thing | owner | notes |
|---|---|---|
| Gregory's movement, collision, camera | **SB** | Minecraft follows; Steve stands at Gregory's feet, eyes at SB's camera |
| block place/break, items, mobs, hand/HUD | **Minecraft** | mouse buttons, wheel and 1-9 are forwarded from SB's window |
| SB's floors in Minecraft | SB → Minecraft | barrier columns (2 blocks thick), only air is replaced, cleared on re-level |
| picture | Minecraft → SB | world colour + depth and hand/HUD overlay, composited by SBCraft.fx against SB's depth |
| control coming back | n/a | Minecraft never moves Gregory (no flight/drive mode yet) |

## Units and axes
- 1 block = 1 m = 100 Unreal units (cm).
- Unreal (x, y, z), left-handed, z up → Minecraft (x/100, z/100 + yOffset, y/100). (Swapping y/z flips handedness.)
- Unreal cell (floor(x/100), floor(y/100)) = Minecraft column (x, z).
- yaw_mc = yaw_ue − 90 (UE yaw 0 = +X = MC east = MC yaw −90); pitch_mc = −pitch_ue; roll_mc = −roll_ue (unverified).
- FOV: Unreal's is horizontal (FMinimalViewInfo.FOV); Minecraft's vertical: vfov = 2·atan(tan(hfov/2)/aspect).
- yOffset = 64 − feet_z/100 at link time or F8, feet_z = capsule centre z − CapsuleHalfHeight.
- Depth: Minecraft 26.1.2 standard Z, GL [-1,1] window depth (flags = 2); SB/UE4 reversed Z, infinite far: dist = near/d,
  near = 0.1 m (default GNearClippingPlane 10 cm — **to calibrate**).

## Channels
`<link>` is `Mods\SBCraft\link` in SB's Win64 folder (or the path in `Mods\SBCraft\link_dir.txt`, or `SBCRAFT_LINK`).
More files there: `sb_blocks.txt` (add-on → Lua: Minecraft block centres), `sb_teleport.txt` (ender pearls),
`sb_actions.txt` (`id melee`, `id explode x y z r`).

| channel | direction | format | rate | full / late |
|---|---|---|---|---|
| `<link>/sb_link.txt` | Lua → add-on | text `key value` lines; gen bumps when PCM/pawn/root change | 1 Hz, temp+rename | add-on treats >5 s stale as invalid |
| `<link>/sb_ground.txt` | Lua → add-on | `seq`, `center`, `x y zTop` per column (UE units) | one pass of 625 traces ≈ 0.35 s | add-on reads at 5 Hz, sends only changed columns |
| `<link>/sb_cmd.txt` | add-on/tools → Lua | lines: `rescan`, `relink` | on demand | deleted when read |
| camera memory | add-on reads SB | FVector loc, FRotator (pitch, yaw, roll), float fov at addresses in sb_link | every present | ReadProcessMemory: bad address → no frame |
| WebSocket 127.0.0.1:25599 | add-on ↔ MC | JSON text (see mc HostLink.java) | cam every present | MC drops cams older than 2 s |
| shm `Local\MCPassthroughFrame` | MC → add-on | 3 slots, seqlock, header layout in FrameExporter.java (v1) | every MC frame | reader skips a slot mid-write |

## Lifecycle
- Either side may start first; the add-on reconnects every second and re-levels + resends ground on reconnect.
- Compositing only while: F7 on, camera readable, link fresh, WebSocket up, pawn is not `DefaultPawn` (menus/loading).
- Lua logic hot-reloads from `sb/lua/sbcraft.lua` (dev) — state table survives reloads.
- SB must run with `-dx11` (ReShade depth path).
