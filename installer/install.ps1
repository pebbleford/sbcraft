# SBCraft one-step installer (no Git, Bash, Java or Visual Studio needed). Run by "Install SBCraft.cmd".
#
#   1. finds Security Breach (every Steam library on every drive, Epic Games, common folders; else asks for the folder)
#   2. downloads UE4SS 3.0.1 and ReShade 6.8.0 from their official sites (SHA-256 checked) and installs them with the
#      SBCraft add-on and Lua mod into SB's Win64 folder (a manifest lists every file, for the uninstaller)
#   3. sets up Minecraft: Fabric Loader 0.19.2 for 26.1.2, an "SBCraft" installation in the Minecraft Launcher with its
#      own game folder (%APPDATA%\.sbcraft-minecraft) and the mod + Fabric API in its mods folder
#   4. puts a "Play SBCraft" shortcut on the desktop (starts the Minecraft Launcher, then SB in -dx11 once Minecraft's
#      SBCraft link is up)
#
#   -GamePath <folder>   use this SB install (any folder in or around it)
#   -Uninstall           remove everything this installer put into SB (and the desktop shortcut)
#   -Force               replace files in SB's folder that another mod put there
#   -SkipMinecraft       only the SB side
#   -MinecraftDir <dir>  another .minecraft folder (default %APPDATA%\.minecraft)
param([string]$GamePath, [switch]$Uninstall, [switch]$Force, [switch]$SkipMinecraft, [string]$MinecraftDir, [switch]$NoPause, [switch]$NoShortcut)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Here = $PSScriptRoot
$Files = Join-Path $Here 'files'
$Cache = Join-Path $env:LOCALAPPDATA 'SBCraft\downloads'
$ExeRel = 'fnaf9\Binaries\Win64\fnaf9-Win64-Shipping.exe'
$McVersion = '26.1.2'
$LoaderVersion = '0.19.2'
$FabricId = "fabric-loader-$LoaderVersion-$McVersion"
$McGameDir = Join-Path $env:APPDATA '.sbcraft-minecraft'
$Deps = @{
	ue4ss   = @{ url = 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip'; sha256 = '4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec'; file = 'UE4SS_v3.0.1.zip' }
	reshade = @{ url = 'https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe'; sha256 = 'afe4c8f13048306307983b8b3d41d5bf00a86820440b0e57dea10950e1176445'; file = 'ReShade_Setup_6.8.0_Addon.exe' }
}
$ShaderIncludes = @('ReShade.fxh', 'ReShadeUI.fxh')

function Say([string]$m, [string]$color = 'Gray') { Write-Host $m -ForegroundColor $color }
function Step([string]$m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Done([int]$code) {
	if (-not $NoPause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
	exit $code
}
function Fail([string]$m) { Write-Host ''; Write-Host "ERROR: $m" -ForegroundColor Red; Done 1 }

# ---------------------------------------------------------------- finding Security Breach
function Resolve-SB([string]$p) {
	if (-not $p) { return $null }
	$p = $p.Trim().Trim('"').TrimEnd('\', '/')
	if (-not (Test-Path -LiteralPath $p)) { return $null }
	$item = Get-Item -LiteralPath $p
	if (-not $item.PSIsContainer) { $item = $item.Directory }
	$up = $item
	for ($i = 0; $i -lt 6 -and $up; $i++) { # inside the install: walk up
		if (Test-Path -LiteralPath (Join-Path $up.FullName $ExeRel)) { return $up.FullName }
		$up = $up.Parent
	}
	$found = Get-ChildItem -LiteralPath $item.FullName -Filter 'fnaf9-Win64-Shipping.exe' -Recurse -Depth 6 -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($found) { return $found.Directory.Parent.Parent.Parent.FullName } # above it: look down
	return $null
}

function Get-SteamLibraries {
	$libs = @()
	$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
	if (-not $steam) { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath }
	if ($steam) {
		$libs += $steam
		$vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
		if (Test-Path $vdf) {
			foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') }
		}
	}
	return $libs | Select-Object -Unique
}

function Find-SB {
	foreach ($lib in Get-SteamLibraries) {
		$r = Resolve-SB (Join-Path $lib 'steamapps\common\Quarters'); if ($r) { return $r }
	}
	$manifests = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
	if (Test-Path $manifests) {
		foreach ($m in Get-ChildItem $manifests -Filter *.item -ErrorAction SilentlyContinue) {
			try { $loc = (Get-Content $m.FullName -Raw | ConvertFrom-Json).InstallLocation } catch { continue }
			$r = Resolve-SB $loc; if ($r) { return $r }
		}
	}
	foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
		foreach ($sub in 'SteamLibrary\steamapps\common\Quarters', 'Steam\steamapps\common\Quarters',
			'Program Files (x86)\Steam\steamapps\common\Quarters', 'Games\Steam\steamapps\common\Quarters',
			'Program Files\Epic Games', 'Epic Games', 'Games') {
			$r = Resolve-SB (Join-Path $d.Root $sub); if ($r) { return $r }
		}
	}
	return $null
}

function Ask-SBFolder {
	Add-Type -AssemblyName System.Windows.Forms
	$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
	$dlg.Description = "Pick your FNAF: Security Breach folder (Steam: right-click the game > Manage > Browse local files)"
	if ($dlg.ShowDialog() -eq 'OK') { return Resolve-SB $dlg.SelectedPath }
	return $null
}

# ---------------------------------------------------------------- files in SB's folder, with a manifest
$script:Manifest = $null
$script:ManifestList = New-Object System.Collections.Generic.List[string]

function Read-Manifest {
	$script:ManifestList.Clear()
	if (Test-Path $script:Manifest) { foreach ($l in Get-Content $script:Manifest) { if ($l) { $script:ManifestList.Add($l) } } }
}
function Save-Manifest { [IO.File]::WriteAllLines($script:Manifest, [string[]]($script:ManifestList | Select-Object -Unique)) }

function Put([string]$src, [string]$rel) {
	# rel uses forward slashes, like sb/install.sh's manifest
	$dst = Join-Path $script:Win64 ($rel -replace '/', '\')
	if ((Test-Path -LiteralPath $dst) -and -not $script:ManifestList.Contains($rel) -and -not $Force) {
		Fail "$rel is already in Security Breach's folder and wasn't installed by SBCraft (another mod?). Run with -Force to replace it."
	}
	$dir = Split-Path -Parent $dst
	if (-not (Test-Path $dir)) {
		New-Item -ItemType Directory -Force -Path $dir | Out-Null
		$d = Split-Path -Parent $rel
		while ($d) { $dd = $d -replace '\\', '/'; if (-not $script:ManifestList.Contains($dd)) { $script:ManifestList.Add($dd) }; $d = Split-Path -Parent $d }
	}
	Copy-Item -LiteralPath $src -Destination $dst -Force
	if (-not $script:ManifestList.Contains($rel)) { $script:ManifestList.Add($rel) }
}

function Get-Download($dep) {
	New-Item -ItemType Directory -Force -Path $Cache | Out-Null
	$out = Join-Path $Cache $dep.file
	$ok = (Test-Path $out) -and ((Get-FileHash $out -Algorithm SHA256).Hash -eq $dep.sha256)
	if (-not $ok) {
		Say "  downloading $($dep.url)"
		Invoke-WebRequest -Uri $dep.url -OutFile $out -UseBasicParsing -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) SBCraft-installer'
		if ((Get-FileHash $out -Algorithm SHA256).Hash -ne $dep.sha256) { Remove-Item $out; Fail "the download of $($dep.file) is not the expected file (checksum). Try again later." }
	}
	return $out
}

# ---------------------------------------------------------------- uninstall
function Remove-SBCraft {
	if (-not (Test-Path $script:Manifest)) { Say 'SBCraft is not installed in this Security Breach (no manifest).'; return }
	Read-Manifest
	foreach ($rel in $script:ManifestList) {
		$p = Join-Path $script:Win64 ($rel -replace '/', '\')
		if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-Item -LiteralPath $p -Force; Say "  removed $rel" }
	}
	$link = Join-Path $script:Win64 'Mods\SBCraft\link'
	if (Test-Path $link) { Remove-Item -Recurse -Force $link }
	foreach ($rel in ($script:ManifestList | Sort-Object { $_.Length } -Descending)) {
		$p = Join-Path $script:Win64 ($rel -replace '/', '\')
		if ((Test-Path -LiteralPath $p -PathType Container) -and -not (Get-ChildItem -LiteralPath $p -Force)) { Remove-Item -LiteralPath $p }
	}
	foreach ($d in 'Mods\SBCraft', 'Mods') { $p = Join-Path $script:Win64 $d; if ((Test-Path $p) -and -not (Get-ChildItem $p -Force)) { Remove-Item $p } }
	Remove-Item -LiteralPath $script:Manifest -Force
	$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Play SBCraft.lnk'
	if (Test-Path $lnk) { Remove-Item $lnk }
	Say 'SBCraft removed from Security Breach.' Green
	Say "The Minecraft side stays: delete the 'SBCraft' installation in the Minecraft Launcher and $McGameDir if you want."
}

# ---------------------------------------------------------------- main
Write-Host 'SBCraft installer' -ForegroundColor Magenta
if (-not (Test-Path (Join-Path $Files 'SBCraft.addon64'))) { Fail "the 'files' folder next to install.ps1 is missing. Extract the whole SBCraft-Installer zip first." }

Step 'Finding FNAF: Security Breach'
$sb = if ($GamePath) { Resolve-SB $GamePath } else { Find-SB }
if (-not $sb) {
	if ($GamePath) { Say "Couldn't find Security Breach in or around: $GamePath" Yellow }
	else { Say "Couldn't find Security Breach automatically: pick its folder." Yellow }
	$sb = Ask-SBFolder
}
if (-not $sb) { Fail "Security Breach wasn't found. Run again and pick the folder that contains 'fnaf9'." }
$script:Win64 = Join-Path $sb 'fnaf9\Binaries\Win64'
$script:Manifest = Join-Path $script:Win64 '.sbcraft_manifest'
Say "  $sb" Green

if (Get-Process -Name 'fnaf9-Win64-Shipping' -ErrorAction SilentlyContinue) { Fail 'Security Breach is running. Quit it and run the installer again.' }

if ($Uninstall) { Step 'Removing SBCraft'; Remove-SBCraft; Done 0 }

Step 'Downloading UE4SS and ReShade (official sites, checksum-checked)'
$ue4ssZip = Get-Download $Deps.ue4ss
$reshadeExe = Get-Download $Deps.reshade
$tmp = Join-Path $env:TEMP ("sbcraft-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$tmp\ue4ss", "$tmp\reshade", "$tmp\shaders" | Out-Null
& "$env:WINDIR\System32\tar.exe" -xf $ue4ssZip -C "$tmp\ue4ss"
if ($LASTEXITCODE -ne 0) { Fail 'could not unpack UE4SS' }
# the ReShade setup carries its DLLs as an appended zip; Windows' tar reads it (Expand-Archive can't)
& "$env:WINDIR\System32\tar.exe" -xf $reshadeExe -C "$tmp\reshade" ReShade64.dll
if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$tmp\reshade\ReShade64.dll")) { Fail 'could not unpack ReShade64.dll from the ReShade setup' }
foreach ($f in $ShaderIncludes) {
	Invoke-WebRequest -Uri "https://raw.githubusercontent.com/crosire/reshade-shaders/slim/Shaders/$f" -OutFile "$tmp\shaders\$f" -UseBasicParsing
}

Step "Installing into Security Breach ($script:Win64)"
Read-Manifest
$ue = "$tmp\ue4ss"
Put "$ue\dwmapi.dll" 'dwmapi.dll'
Put "$ue\UE4SS.dll" 'UE4SS.dll'
(Get-Content "$ue\UE4SS-settings.ini") -replace '^GuiConsoleEnabled = 1', 'GuiConsoleEnabled = 0' | Set-Content "$tmp\UE4SS-settings.ini"
Put "$tmp\UE4SS-settings.ini" 'UE4SS-settings.ini'
foreach ($f in Get-ChildItem "$ue\Mods" -Recurse -File) {
	$rel = 'Mods/' + ($f.FullName.Substring("$ue\Mods\".Length) -replace '\\', '/')
	if ($rel -ne 'Mods/mods.txt') { Put $f.FullName $rel }
}
$modsTxt = @()
$added = $false
foreach ($l in Get-Content "$ue\Mods\mods.txt") {
	if (-not $added -and $l -match '^; Built-in keybinds') { $modsTxt += 'SBCraft : 1'; $modsTxt += ''; $added = $true }
	$modsTxt += $l
}
if (-not $added) { $modsTxt += 'SBCraft : 1' }
Set-Content "$tmp\mods.txt" $modsTxt
Put "$tmp\mods.txt" 'Mods/mods.txt'
Put (Join-Path $Files 'sb\Mods\SBCraft\Scripts\main.lua') 'Mods/SBCraft/Scripts/main.lua'
Put (Join-Path $Files 'sb\Mods\SBCraft\Scripts\sbcraft.lua') 'Mods/SBCraft/Scripts/sbcraft.lua'
Put "$tmp\reshade\ReShade64.dll" 'dxgi.dll'
Put (Join-Path $Files 'SBCraft.addon64') 'SBCraft.addon64'
Put (Join-Path $Files 'sb\ReShade.ini') 'ReShade.ini'
Put (Join-Path $Files 'sb\ReShadePreset.ini') 'ReShadePreset.ini'
Put (Join-Path $Files 'sb\reshade-shaders\Shaders\SBCraft.fx') 'reshade-shaders/Shaders/SBCraft.fx'
foreach ($f in $ShaderIncludes) { Put "$tmp\shaders\$f" "reshade-shaders/Shaders/$f" }
New-Item -ItemType Directory -Force -Path (Join-Path $script:Win64 'Mods\SBCraft\link') | Out-Null
Save-Manifest
Remove-Item -Recurse -Force $tmp
Say "  done ($($script:ManifestList.Count) entries in .sbcraft_manifest)" Green

if (-not $SkipMinecraft) {
	Step 'Setting up Minecraft (Fabric + the SBCraft installation)'
	$mc = if ($MinecraftDir) { $MinecraftDir } else { Join-Path $env:APPDATA '.minecraft' }
	if (-not (Test-Path $mc)) {
		Say "  no Minecraft folder at ${mc}: install Minecraft Java Edition, start it once, then run this installer again." Yellow
	} else {
		while (-not $MinecraftDir -and (Get-Process -Name 'MinecraftLauncher', 'Minecraft' -ErrorAction SilentlyContinue)) {
			Read-Host '  Close the Minecraft Launcher (it would undo the new installation), then press Enter' | Out-Null
		}
		# Fabric Loader: the version profile the official installer writes (the launcher downloads the libraries)
		$vdir = Join-Path $mc "versions\$FabricId"
		if (-not (Test-Path (Join-Path $vdir "$FabricId.json"))) {
			New-Item -ItemType Directory -Force -Path $vdir | Out-Null
			Invoke-WebRequest -Uri "https://meta.fabricmc.net/v2/versions/loader/$McVersion/$LoaderVersion/profile/json" -OutFile (Join-Path $vdir "$FabricId.json") -UseBasicParsing
			[IO.File]::WriteAllBytes((Join-Path $vdir "$FabricId.jar"), [byte[]](80, 75, 5, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) # an empty jar
			Say "  Fabric Loader $LoaderVersion for $McVersion added"
		} else { Say "  Fabric Loader $LoaderVersion for $McVersion already there" }
		# the game folder, with the mods
		$mods = Join-Path $McGameDir 'mods'
		New-Item -ItemType Directory -Force -Path $mods | Out-Null
		Get-ChildItem $mods -Filter 'sbcraft-*.jar' -ErrorAction SilentlyContinue | Remove-Item -Force
		Get-ChildItem $mods -Filter "fabric-api-*+$McVersion.jar" -ErrorAction SilentlyContinue | Remove-Item -Force
		foreach ($jar in Get-ChildItem $Files -Filter *.jar) { Copy-Item $jar.FullName $mods -Force; Say "  mods\$($jar.Name)" }
		# the launcher installation
		$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
		foreach ($pf in 'launcher_profiles.json', 'launcher_profiles_microsoft_store.json') {
			$path = Join-Path $mc $pf
			if (-not (Test-Path $path)) {
				if ($pf -eq 'launcher_profiles.json') { [IO.File]::WriteAllText($path, '{"profiles":{},"settings":{},"version":3}') } else { continue }
			}
			Copy-Item $path "$path.sbcraft-backup" -Force
			$json = Get-Content $path -Raw | ConvertFrom-Json
			if (-not $json.profiles) { $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) -Force }
			$profile = [pscustomobject]@{
				created = $now; lastUsed = $now; icon = 'TNT'; name = 'SBCraft'; type = 'custom'
				lastVersionId = $FabricId; gameDir = $McGameDir; javaArgs = '-Xmx3G -XX:+UseG1GC'
			}
			$json.profiles | Add-Member -NotePropertyName 'sbcraft' -NotePropertyValue $profile -Force
			[IO.File]::WriteAllText($path, ($json | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding($false)))
			Say "  'SBCraft' installation added to $pf"
		}
	}
}

if (-not $NoShortcut) {
Step 'Desktop shortcut'
$play = Join-Path $Here 'Play SBCraft.cmd'
$lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Play SBCraft.lnk'
$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($lnkPath)
$lnk.TargetPath = $play
$lnk.WorkingDirectory = $Here
$lnk.IconLocation = (Join-Path $script:Win64 'fnaf9-Win64-Shipping.exe') + ',0'
$lnk.Description = 'Start Minecraft (SBCraft) and FNAF: Security Breach together'
$lnk.Save()
Say "  $lnkPath" Green
}

Write-Host ''
Write-Host 'SBCraft is installed!' -ForegroundColor Green
Write-Host '  Double-click "Play SBCraft" on your desktop: in the Minecraft Launcher pick the "SBCraft" installation and'
Write-Host '  press Play. Security Breach starts by itself once Minecraft is ready. Leave the Minecraft window open.'
Write-Host '  Keep this folder: the shortcut runs from it. To remove SBCraft: "Uninstall SBCraft.cmd".'
Done 0
