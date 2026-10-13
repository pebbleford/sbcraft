# Modrinth modpack

Everything needed to publish the Minecraft half of SBCraft on [Modrinth](https://modrinth.com) as a modpack.

| file | what it is |
|---|---|
| `dist/SBCraft-0.1.0.mrpack` | the modpack (build it, see below) |
| `description.md` | the project page body |
| `project.json` | the values to enter on Modrinth: name, slug, summary, categories, sides, license, links, gallery captions, version info |
| `icon.png` | 512×512 project icon (original pixel art, `make_icon.py`) |
| `gallery/*.jpg` | screenshots for the gallery |

## Build the pack

```bash
cd mc && ./gradlew build
```

```bash
python modrinth/build_mrpack.py
```

`SBCraft-0.1.0.mrpack` contains:

- **`modrinth.index.json`**: Minecraft 26.1.2 and Fabric Loader 0.19.2, plus Fabric API 0.155.3, referenced from
  Modrinth's CDN with its SHA-1/SHA-512.
- **`overrides/mods/sbcraft-0.1.0.jar`**: the mod itself.

To try it locally, import the file in the Modrinth App (**+ → Import from file**).

## Publish

1. **Make the GitHub repository public.** The page links to it for the Security Breach half and the source.
   ```bash
   gh repo edit pebbleford/sbcraft --visibility public --accept-visibility-change-consequences
   ```
2. **Create the project.** On modrinth.com, go to **Create a project → Modpack**. Use the name, URL slug and summary
   from `project.json`, set visibility, then create it.
3. **Fill in the project page:**
   - Upload `icon.png`.
   - Paste `description.md` into **Description**.
   - Set categories, client side *required* / server side *unsupported*, and the MIT license.
   - Add the source and issue links.
   - Upload the gallery images with their captions.
4. **Create a version.** Upload `dist/SBCraft-0.1.0.mrpack`, then use version number `0.1.0`, type beta, game version
   26.1.2, loader Fabric, and the changelog from `project.json`.
5. **Submit for review.**

Modrinth moderators review every new project. This pack only works together with software outside Minecraft (the
Security Breach side), and the description says so up front. Expect questions about that, about the AI-built
disclosure, and about the game screenshots.
