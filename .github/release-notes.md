## Easiest: the one-step installer

1. Download **`SBCraft-Installer-<version>.zip`** below and extract it somewhere you'll keep, for example
   `Documents\SBCraft`.
2. Close Security Breach and the Minecraft Launcher, then double-click **`Install SBCraft.cmd`**.
   - It finds Security Breach on any drive, or asks for its folder.
   - It downloads UE4SS and ReShade from their official sites and installs SBCraft into SB.
   - It adds Fabric and an **SBCraft** installation (with the mods) to the Minecraft Launcher.
   - It puts **Play SBCraft** on your desktop.
3. Double-click **Play SBCraft**. In the Minecraft Launcher, pick the **SBCraft** installation and press Play.
   Security Breach starts by itself in D3D11 mode once Minecraft is ready. Then load your save.

No Git, Java or Visual Studio needed. If Windows says "Windows protected your PC", choose **More info → Run anyway**.
To remove it, use `Uninstall SBCraft.cmd`.

## Downloads

| file | what it is |
|---|---|
| `SBCraft-Installer-<version>.zip` | the one-step installer (everything below, plus the install/play/uninstall scripts) |
| `sbcraft-<version>.jar` | the SBCraft Minecraft mod (Fabric, Minecraft **26.1.2**) |
| `fabric-api-0.155.3+26.1.2.jar` | Fabric API, which the mod needs (Apache-2.0, re-hosted unchanged from Modrinth) |
| `SBCraft-<version>.mrpack` | the two jars as a Modrinth modpack: import it in the Modrinth App (**+ → Import from file**) |
| `SBCraft.addon64` | the prebuilt Security Breach add-on (ReShade), so you don't need Visual Studio |

## Manual install (if you prefer)

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
   It finds SB on any drive. If it can't, give it the game folder:
   `bash sb/install.sh "D:\SteamLibrary\steamapps\common\Quarters"`.
3. **Play.** Start SB with the launch option `-dx11`, start Minecraft with the SBCraft instance, and load your save.

Full instructions are in the [README](../../#install). This release is rebuilt automatically on every push to
`main`; a version bump in `mc/gradle.properties` makes a new release.
