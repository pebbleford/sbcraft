# SBCraft: Minecraft inside FNAF: Security Breach

**Real Minecraft, running next to *Five Nights at Freddy's: Security Breach* and drawn inside it.** You walk the
Pizzaplex as Gregory, with Minecraft's hand and hotbar, and build in it.

> ⚠️ **This modpack is only the Minecraft half.** SBCraft also needs the Security Breach side: UE4SS, ReShade and the
> SBCraft add-on, installed into your own copy of the game. Set that up from the
> [GitHub repository](https://github.com/pebbleford/sbcraft) first. Windows only, single-player only.

## What it does

- 🧱 **Build in the Pizzaplex.** Place and break blocks on SB's floors and walls. Blocks are depth-tested against SB,
  so its walls hide them, and they're lit to match its darkness.
- 🚧 **Blocks are solid in SB.** Every block you place becomes an invisible wall in SB. Gregory can't walk through it,
  and animatronics run into it.
- ⚔️ **The diamond sword stuns animatronics** using the game's own stun.
- 💥 **TNT and creepers** stun animatronics and blow away props, vents, lamps and wall panels. Floors, doors and save
  stations are never touched.
- 🟣 **Ender pearls** teleport Gregory.
- 🏹 **Bows, crossbows and fireworks.** Arrows stick in SB's walls.

## How it works

Minecraft renders from Security Breach's camera, and SB's floors and walls become invisible barriers in Minecraft. A
ReShade add-on blends Minecraft's picture (colour and depth) into SB's frame. A UE4SS Lua mod gives the blocks you
place real collision in SB and turns the sword, TNT and pearls into SB actions. Full write-up in the repository.

## Install

1. Install this modpack in the Modrinth App (or any launcher that imports `.mrpack`). It sets up Minecraft
   **26.1.2**, **Fabric Loader 0.19.2** and Fabric API, plus the SBCraft mod.
2. Install the Security Breach side by following the [README](https://github.com/pebbleford/sbcraft#install). Start
   SB with `-dx11`.
3. Start this instance and leave its window open, then start Security Breach and load your save.

The mod creates its own empty creative world (`passthrough`) and opens it automatically. Keep this pack in its own
instance.

## Controls (with SB focused)

| Key | Action |
|---|---|
| Left mouse | Attack: break blocks, swing the sword |
| Right mouse | Use: place blocks, light TNT, shoot, throw pearls |
| Wheel / 1–9 | Hotbar |
| F7 | Passthrough on/off |
| F8 | Re-level the floor where you stand |

## Notes

- **Requirements:** Windows, *FNAF: Security Breach* on Steam, and its D3D11 mode (ray tracing off).
- **Single-player only.** The local link listens on `127.0.0.1:25599` with no authentication.
- **Built with AI.** This was made with Claude Code using the
  [universal-modder](https://github.com/rehan-remade/universal-modder) toolkit, and adapts its MIT-licensed
  Minecraft × GTA V passthrough example.
- **No game files** from Security Breach or Minecraft are included.
- **Unofficial fan project.** Not affiliated with Steel Wool Studios, Scott Cawthon, Mojang or Microsoft.
