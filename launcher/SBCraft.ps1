# SBCraft launcher: starts Minecraft (the sbcraft Fabric dev client), then Security Breach in D3D11 mode, waits for SB
# to quit and then closes the Minecraft it started. Run by SBCraft.exe (the Steam shortcut); logs to run\launcher.log.
#   -NoMinecraft   only start SB (Minecraft is started some other way, e.g. a launcher profile)
param([switch]$NoMinecraft)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Run = Join-Path $Root 'run'
New-Item -ItemType Directory -Force -Path $Run | Out-Null
$Log = Join-Path $Run 'launcher.log'
$SbAppId = 747660
$SbArgs = @('-dx11', '-windowed', '-ResX=1920', '-ResY=1080')
$SbProcess = 'fnaf9-Win64-Shipping'
$Port = 25599

function Log([string]$m) { Add-Content -Path $Log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" }

function Test-MinecraftLink {
	$c = New-Object Net.Sockets.TcpClient
	try { $c.Connect('127.0.0.1', $Port); return $true } catch { return $false } finally { $c.Close() }
}

function Get-SteamExe {
	$p = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamExe
	if ($p -and (Test-Path $p)) { return $p }
	return 'C:\Program Files (x86)\Steam\steam.exe'
}

function Get-SbWin64 {
	$steam = Split-Path -Parent (Get-SteamExe)
	$libs = @($steam)
	$vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
	if (Test-Path $vdf) {
		foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value -replace '\\\\', '\' }
	}
	foreach ($lib in $libs) {
		$w = Join-Path $lib 'steamapps\common\Quarters\fnaf9\Binaries\Win64'
		if (Test-Path (Join-Path $w 'fnaf9-Win64-Shipping.exe')) { return $w }
	}
	return $null
}

function Show-Error([string]$m) {
	Log "ERROR $m"
	Add-Type -AssemblyName PresentationFramework
	[System.Windows.MessageBox]::Show($m, 'SBCraft') | Out-Null
}

Log "---- launch (root $Root)"

# 0. SB side installed?
$win64 = Get-SbWin64
if (-not $win64) { Show-Error 'FNAF: Security Breach was not found in your Steam libraries.'; exit 1 }
if (-not (Test-Path (Join-Path $win64 'SBCraft.addon64')) -or -not (Test-Path (Join-Path $win64 'dwmapi.dll'))) {
	Show-Error "SBCraft isn't installed into Security Breach yet. Run: bash sb/install.sh (see README)."
	exit 1
}

# 1. Minecraft
$startedMc = $false
if (-not $NoMinecraft) {
	if (Test-MinecraftLink) {
		Log 'Minecraft is already running (link port open)'
	} else {
		$gradlew = Join-Path $Root 'mc\gradlew.bat'
		if (-not (Test-Path (Join-Path $Root 'mc\build\libs'))) { Log 'mc not built yet: runClient will build it first' }
		Log 'starting Minecraft (gradlew runClient)'
		Start-Process -FilePath $gradlew -ArgumentList 'runClient', '--console=plain' -WorkingDirectory (Join-Path $Root 'mc') `
			-WindowStyle Hidden -RedirectStandardOutput (Join-Path $Run 'minecraft.log') -RedirectStandardError (Join-Path $Run 'minecraft.err.log') | Out-Null
		$startedMc = $true
		$deadline = (Get-Date).AddSeconds(240)
		while (-not (Test-MinecraftLink)) {
			if ((Get-Date) -gt $deadline) { Show-Error "Minecraft didn't start within 4 minutes. See run\minecraft.log."; exit 1 }
			Start-Sleep -Seconds 2
		}
		Log 'Minecraft link is up'
	}
}

# 2. Security Breach (through Steam, with the D3D11 launch options the compositor needs)
$sb = Get-Process -Name $SbProcess -ErrorAction SilentlyContinue | Select-Object -First 1
if ($sb) {
	Log "Security Breach is already running (pid $($sb.Id))"
} else {
	Log "starting Security Breach: steam -applaunch $SbAppId $($SbArgs -join ' ')"
	Start-Process -FilePath (Get-SteamExe) -ArgumentList (@('-applaunch', "$SbAppId") + $SbArgs) | Out-Null
	$deadline = (Get-Date).AddSeconds(180)
	while (-not $sb) {
		if ((Get-Date) -gt $deadline) { Show-Error "Security Breach didn't start within 3 minutes."; break }
		Start-Sleep -Seconds 2
		$sb = Get-Process -Name $SbProcess -ErrorAction SilentlyContinue | Select-Object -First 1
	}
}

# 3. While SB runs, Steam shows SBCraft as playing; when it quits, close the Minecraft we started
if ($sb) {
	Log "Security Breach running (pid $($sb.Id)), waiting for it to quit"
	$sb.WaitForExit()
	Log 'Security Breach quit'
}
if ($startedMc) {
	$mc = Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" |
		Where-Object { $_.CommandLine -match 'KnotClient|devlaunchinjector' -and $_.CommandLine -match [regex]::Escape((Join-Path $Root 'mc')) }
	foreach ($p in $mc) {
		Log "closing Minecraft (pid $($p.ProcessId))"
		Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
	}
}
Log 'done'
