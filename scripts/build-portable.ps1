param(
    [string]$Version = '0.1.0',
    [string]$ScrcpyVersion = '4.1',
    [string]$ScrcpySha256 = '5b12172b3264b2889f4583ee64752ce832e29bc8b1089dca81093459697165db'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$distPath = Join-Path $projectRoot 'dist'
$stagePath = Join-Path $distPath "Gomdory-Mirror-Portable-v$Version"
$downloadPath = Join-Path $distPath "scrcpy-win64-v$ScrcpyVersion.zip"
$downloadUrl = "https://github.com/Genymobile/scrcpy/releases/download/v$ScrcpyVersion/scrcpy-win64-v$ScrcpyVersion.zip"

if (Test-Path -LiteralPath $stagePath) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force
}
New-Item -ItemType Directory -Path $stagePath | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagePath 'app') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagePath 'tools\scrcpy') | Out-Null

Write-Host "scrcpy v$ScrcpyVersion 다운로드 중..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath
$actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $ScrcpySha256.ToLowerInvariant()) {
    throw "scrcpy 파일의 SHA-256이 일치하지 않습니다. 예상: $ScrcpySha256 / 실제: $actualHash"
}

$expandedPath = Join-Path $distPath 'scrcpy-expanded'
if (Test-Path -LiteralPath $expandedPath) {
    Remove-Item -LiteralPath $expandedPath -Recurse -Force
}
Expand-Archive -LiteralPath $downloadPath -DestinationPath $expandedPath -Force
$scrcpyFolder = Get-ChildItem -LiteralPath $expandedPath -Directory | Select-Object -First 1
if ($null -eq $scrcpyFolder) { throw 'scrcpy 압축 구조를 확인할 수 없습니다.' }

$launcherSource = Join-Path $projectRoot '곰도리 미러 시작.cmd'
$launcherDestination = Join-Path $stagePath '곰도리 미러 시작.cmd'
$launcherText = [System.IO.File]::ReadAllText($launcherSource)
$launcherText = [regex]::Replace($launcherText, "`r?`n", "`r`n")
[System.IO.File]::WriteAllText(
    $launcherDestination,
    $launcherText,
    [System.Text.UTF8Encoding]::new($false)
)
Copy-Item -LiteralPath (Join-Path $projectRoot 'app\GomdoryMirror.ps1') -Destination (Join-Path $stagePath 'app')
Copy-Item -LiteralPath (Join-Path $projectRoot '처음 연결하기.txt') -Destination $stagePath
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $stagePath
Copy-Item -LiteralPath (Join-Path $projectRoot 'NOTICE') -Destination $stagePath
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $stagePath
Copy-Item -Path (Join-Path $scrcpyFolder.FullName '*') -Destination (Join-Path $stagePath 'tools\scrcpy') -Recurse -Force

$zipPath = Join-Path $distPath "Gomdory-Mirror-Portable-v$Version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stagePath '*') -DestinationPath $zipPath -CompressionLevel Optimal

$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$zipPath.sha256" -Value "$zipHash  $(Split-Path -Leaf $zipPath)" -Encoding ascii
Write-Host "완료: $zipPath"
