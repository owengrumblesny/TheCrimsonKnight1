# Crimson Knight: publish a GitHub Release so every installed copy auto-updates.
#
#   powershell -ExecutionPolicy Bypass -File build/publish_release.ps1 -Version 0.9.1 -Notes "What changed"
#
# 1. writes the version into config/version.json, builds the game and CrimsonKnight-Setup.exe
# 2. commits the version bump and pushes master to origin/main
# 3. creates the release v<version> and uploads CrimsonKnight-Setup.exe (plus the Linux .tar.gz if built)
# The game checks the repo's latest release when Play is pressed (godot/scripts/systems/updater.gd).
# Uses `gh` when it is logged in; otherwise the GitHub credentials git already stores.
#
# Updating only R.E.D.'s AI dependencies needs no release: edit config/ai_manifest.json (bump "version", change
# the URLs) and push. Installed games read the live copy from the main branch.

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Notes = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$cfgPath = Join-Path $Repo 'config\version.json'
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$cfg.version = $Version
[IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json) + "`n")
$Slug = $cfg.repo
$Tag = "v$Version"

if (-not $SkipBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build_windows.ps1') -NoAI -Installer
    if ($LASTEXITCODE -ne 0) { throw "Build failed." }
}
$Setup = Join-Path $Repo 'dist\CrimsonKnight-Setup.exe'
if (-not (Test-Path $Setup)) { throw "Missing $Setup" }

# git reports progress on stderr, and "nothing to commit" is fine when the version didn't change
$ErrorActionPreference = 'Continue'
git -C $Repo add config/version.json *> $null
git -C $Repo -c user.name="Owen Grumbles" -c user.email="owengrumblesny@gmail.com" commit -m "Release $Tag" *> $null
git -C $Repo push origin master:main *> $null
if ($LASTEXITCODE -ne 0) { throw "git push failed." }
$ErrorActionPreference = 'Stop'

$linux = Get-ChildItem (Join-Path $Repo 'dist') -Filter 'CrimsonKnight-*-linux-x86_64.tar.gz' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
$linuxAsset = $null
if ($linux) {
    # the updater looks for this exact name
    $linuxAsset = Join-Path $linux.DirectoryName 'CrimsonKnight-linux.tar.gz'
    Copy-Item $linux.FullName $linuxAsset -Force
}

$ghOk = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ErrorActionPreference = 'Continue'
    gh auth status *> $null
    $ghOk = $LASTEXITCODE -eq 0
    $ErrorActionPreference = 'Stop'
}
if ($ghOk) {
    $assets = @($Setup)
    if ($linuxAsset) { $assets += $linuxAsset }
    gh release create $Tag @assets --repo $Slug --title "Crimson Knight $Version" --notes $Notes
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed." }
} else {
    # no gh: use the token git's credential manager already holds for github.com
    $cred = "protocol=https`nhost=github.com`n`n" | git credential fill
    $token = (($cred | Where-Object { $_ -like 'password=*' }) -replace '^password=', '')
    if (-not $token) { throw "No GitHub credentials found. Run: gh auth login" }
    $h = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'CrimsonKnight-Release' }
    $body = @{ tag_name = $Tag; name = "Crimson Knight $Version"; body = $Notes; target_commitish = 'main' } | ConvertTo-Json
    $rel = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Slug/releases" -Headers $h -Body $body -ContentType 'application/json'
    $files = @($Setup)
    if ($linuxAsset) { $files += $linuxAsset }
    foreach ($f in $files) {
        $name = Split-Path $f -Leaf
        $mb = [math]::Round((Get-Item $f).Length / 1MB)
        Write-Host "Uploading $name ($mb MB)..."
        $up = ($rel.upload_url -replace '\{.*\}', '') + "?name=$name"
        Invoke-RestMethod -Method Post -Uri $up -Headers $h -InFile $f -ContentType 'application/octet-stream' -TimeoutSec 7200 | Out-Null
    }
}
Write-Host "Released $Tag. Installed games will offer this update at their next launch." -ForegroundColor Green
