# Crimson Knight: export the Windows build to dist/windows/CrimsonKnight.exe and copy the R.E.D. ai/ folder next to it.
#
#   powershell -ExecutionPolicy Bypass -File build/build_windows.ps1            # release build with ai/
#   powershell -ExecutionPolicy Bypass -File build/build_windows.ps1 -NoAI      # game only
#   powershell -ExecutionPolicy Bypass -File build/build_windows.ps1 -Installer # also build dist/CrimsonKnight-Setup.exe
#   powershell -ExecutionPolicy Bypass -File build/build_windows.ps1 -DebugBuild # debug template
#
# Godot: $env:GODOT, else Godot on PATH, else the WinGet install. ai/: $env:CK_AI_DIR, else <repo>/ai, else the
# main checkout's ai/ when run from a git worktree. Needs the 4.7.2 export templates (see docs/BUILD.md).

param(
    [switch]$NoAI,
    [switch]$Installer,
    [switch]$DebugBuild
)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Repo 'dist\windows'
$OutExe = Join-Path $OutDir 'CrimsonKnight.exe'

function Fail([string]$msg) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

# ---- Godot ----
$WinGetGodot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe'
$Godot = $env:GODOT
if (-not $Godot) {
    $cmd = Get-Command 'Godot_v4.7.2-stable_win64_console.exe', 'godot' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $Godot = $cmd.Source } elseif (Test-Path $WinGetGodot) { $Godot = $WinGetGodot }
}
if (-not $Godot -or -not (Test-Path $Godot)) {
    Fail "Godot 4.7.2 not found. Set `$env:GODOT to Godot_v4.7.2-stable_win64_console.exe (winget install GodotEngine.GodotEngine)."
}

# ---- export templates ----
# "4.7.2.stable.official.abc123" -> "4.7.2.stable" (the templates folder name)
$Version = ((& $Godot --version) | Select-Object -Last 1).Trim()
$TplVersion = ($Version -split '\.')[0..3] -join '.'
$TplDir = Join-Path $env:APPDATA "Godot\export_templates\$TplVersion"
$Tpl = Join-Path $TplDir ($(if ($DebugBuild) { 'windows_debug_x86_64.exe' } else { 'windows_release_x86_64.exe' }))
if (-not (Test-Path $Tpl)) {
    Fail ("Export templates for Godot $TplVersion are not installed (missing $Tpl).`n" +
        "       Install them from the Godot editor (Editor > Manage Export Templates > Download and Install)`n" +
        "       or see docs/BUILD.md for the .tpz download.")
}

# ---- export ----
New-Item -ItemType Directory -Force $OutDir | Out-Null
# keep Godot from scanning dist/ (exported binaries, the copied ai/ folder) as project files
New-Item -ItemType File -Force (Join-Path $Repo 'dist\.gdignore') | Out-Null
$Mode = $(if ($DebugBuild) { '--export-debug' } else { '--export-release' })
Write-Host "Exporting with $Godot ($Version)..."
& $Godot --headless --path $Repo $Mode 'Windows Desktop' $OutExe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutExe)) {
    Fail "Godot export failed (exit $LASTEXITCODE). See the output above."
}

# ---- R.E.D. ai/ ----
if (-not $NoAI) {
    $AiSrc = $env:CK_AI_DIR
    if (-not $AiSrc) {
        $AiSrc = Join-Path $Repo 'ai'
        if (-not (Test-Path $AiSrc)) {
            # in a git worktree, ai/ (git-ignored) lives in the main checkout
            $common = (& git -C $Repo rev-parse --path-format=absolute --git-common-dir 2>$null)
            if ($common) { $AiSrc = Join-Path (Split-Path -Parent $common) 'ai' }
        }
    }
    if ($AiSrc -and (Test-Path (Join-Path $AiSrc 'llama\llama-server.exe'))) {
        Write-Host "Copying R.E.D. ai/ from $AiSrc..."
        # /MIR keeps dist/windows/ai an exact copy; robocopy exit codes below 8 mean success
        robocopy $AiSrc (Join-Path $OutDir 'ai') /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { Fail "Copying ai/ failed (robocopy exit $LASTEXITCODE)." }
        $global:LASTEXITCODE = 0
    } else {
        Write-Warning "R.E.D. ai/ folder not found (looked in '$AiSrc'); the build runs with scripted R.E.D. lines only. Use -NoAI to silence."
    }
}

Write-Host "Built $OutExe" -ForegroundColor Green

# ---- installer ----
if ($Installer) {
    $Iscc = $env:ISCC
    if (-not $Iscc) {
        $Iscc = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
            "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 7\ISCC.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $Iscc) { Fail "Inno Setup 6 (ISCC.exe) not found. Install it (see docs/BUILD.md) or set `$env:ISCC." }
    & $Iscc (Join-Path $PSScriptRoot 'installer\crimson_knight.iss')
    if ($LASTEXITCODE -ne 0) { Fail "Inno Setup failed (exit $LASTEXITCODE)." }
    Write-Host "Built $(Join-Path $Repo 'dist\CrimsonKnight-Setup.exe')" -ForegroundColor Green
}
