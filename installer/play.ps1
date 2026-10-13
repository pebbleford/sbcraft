# Play SBCraft: opens the Minecraft Launcher (you press Play on the "SBCraft" installation), waits until the sbcraft mod's
# link is up, then starts FNAF: Security Breach through Steam in D3D11 mode (which SBCraft needs).
$ErrorActionPreference = 'Stop'
$Port = 25599

function Test-Link {
	$c = New-Object Net.Sockets.TcpClient
	try { $c.Connect('127.0.0.1', $Port); return $true } catch { return $false } finally { $c.Close() }
}

function Start-MinecraftLauncher {
	foreach ($exe in "${env:ProgramFiles(x86)}\Minecraft Launcher\MinecraftLauncher.exe", "$env:ProgramFiles\Minecraft Launcher\MinecraftLauncher.exe",
		'C:\XboxGames\Minecraft Launcher\Content\Minecraft.exe') {
		if ($exe -and (Test-Path $exe)) { Start-Process $exe; return $true }
	}
	$app = Get-StartApps -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Minecraft Launcher' } | Select-Object -First 1
	if ($app) { Start-Process "shell:AppsFolder\$($app.AppID)"; return $true }
	return $false
}

Write-Host 'SBCraft' -ForegroundColor Magenta
if (-not (Test-Link)) {
	if (-not (Start-MinecraftLauncher)) {
		Write-Host "Couldn't find the Minecraft Launcher: start it yourself." -ForegroundColor Yellow
	}
	Write-Host 'In the Minecraft Launcher, pick the "SBCraft" installation and press Play.' -ForegroundColor Cyan
	Write-Host 'Waiting for Minecraft... (Security Breach starts by itself; leave the Minecraft window open)'
	while (-not (Test-Link)) { Start-Sleep -Seconds 2 }
}
Write-Host 'Minecraft is ready. Starting Security Breach...' -ForegroundColor Green
$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamExe
if ($steam -and (Test-Path $steam)) {
	Start-Process $steam -ArgumentList '-applaunch', '747660', '-dx11', '-windowed', '-ResX=1920', '-ResY=1080'
} else {
	Write-Host 'Steam not found: start Security Breach yourself with the launch option -dx11.' -ForegroundColor Yellow
	Read-Host 'Press Enter to close' | Out-Null
	exit 1
}
Start-Sleep -Seconds 5
