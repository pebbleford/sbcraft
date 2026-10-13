## Downloads

| file | what it is |
|---|---|
| `sbcraft-<version>.jar` | the SBCraft Minecraft mod (Fabric, Minecraft **26.1.2**) |
| `fabric-api-0.155.3+26.1.2.jar` | Fabric API, which the mod needs (Apache-2.0, re-hosted unchanged from Modrinth) |
| `SBCraft-<version>.mrpack` | the same two in a Modrinth modpack: import it in the Modrinth App (**+ → Import from file**) |
| `SBCraft.addon64` | the prebuilt Security Breach add-on (ReShade), so you don't need Visual Studio |

## Install for a friend (short version)

1. **Minecraft side.** Use one of these:
   - Import `SBCraft-<version>.mrpack` into the Modrinth App.
   - Or install Fabric Loader 0.19.2+ for 26.1.2, make a separate launcher installation with its own game folder,
     and put both `.jar` files into its `mods` folder.
2. **Security Breach side.** Clone or download this repository, then put `SBCraft.addon64` into
   `sb/addon/build/`. In Git Bash, run:
   ```bash
   bash scripts/fetch_deps.sh
   ```
   ```bash
   bash sb/install.sh
   ```
   It finds SB on any drive (every Steam library). If it can't, run it as
   `SB_DIR="D:\SteamLibrary\steamapps\common\Quarters" bash sb/install.sh`.
3. **Play.** Start SB with the launch option `-dx11`, start Minecraft with the SBCraft instance, and load your save.

Full instructions are in the [README](../../#install). This release is rebuilt automatically on every push to
`main`; a version bump in `mc/gradle.properties` makes a new release.
