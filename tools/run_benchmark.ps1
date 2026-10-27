# Crimson Knight: Earth-RED — run the in-game benchmark on this PC (needs `npm run dev` running in game/).
# Opens a separate 1280x720 Edge window (throwaway profile, your normal browser is untouched) that runs
# all six benchmark scenes on each preset in turn. Each report is saved to docs/benchmarks/*.json.
# Keep the window visible and don't use the PC heavily until it shows the ULTRA results (~3 minutes).
param([string]$Presets = 'low,medium,high,ultra')

$first, $rest = $Presets.Split(',', 2)
$profileDir = Join-Path $env:LOCALAPPDATA 'Temp\ck-bench-profile'
New-Item -ItemType Directory -Force $profileDir | Out-Null
$url = "http://localhost:5173/?nolock&bench&quality=$first&then=$rest"
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
Start-Process -FilePath $edge -ArgumentList @("--user-data-dir=$profileDir", '--no-first-run', '--no-default-browser-check',
  '--window-size=1296,759', '--window-position=40,40', "--app=$url")
Write-Host "Benchmark started ($Presets). Results -> docs\benchmarks\"
