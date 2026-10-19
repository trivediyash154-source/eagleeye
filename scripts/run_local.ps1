# EAGLE EYE - one-command local run for Windows:  API + web console on http://localhost:8000
#
#   powershell -ExecutionPolicy Bypass -File scripts\run_local.ps1            first run installs everything
#   powershell -ExecutionPolicy Bypass -File scripts\run_local.ps1 -Port 8080
#
# Requirements: Python 3.11-3.13 for Windows x64 (python.org installer, 3.11 recommended), ~5 GB free disk.
# Flutter is NOT required: a prebuilt web console is committed in frontend\prebuilt\web.
param([int]$Port = 0)   # 0 = 8000, or the next free port up to 8010
# Native tools (py, pip) write warnings to stderr; exit codes are checked explicitly instead.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $PSScriptRoot
$Venv = if ($env:EAGLEEYE_VENV) { $env:EAGLEEYE_VENV } else { Join-Path $Root '.venv' }
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$VenvPy = if ($OnWindows) { Join-Path $Venv 'Scripts\python.exe' } else { Join-Path $Venv 'bin/python' }

function Say($m) { Write-Host "[eagle-eye] $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "[eagle-eye] $m" -ForegroundColor Red; exit 1 }

function Find-Python {
  if ($env:PYTHON) { return , @($env:PYTHON) }
  $candidates = @(@('py', '-3.11'), @('py', '-3.12'), @('py', '-3.13'), @('python'), @('python3'))
  foreach ($c in $candidates) {
    if (-not (Get-Command $c[0] -ErrorAction SilentlyContinue)) { continue }
    $exe = $c[0]; $pre = @($c | Select-Object -Skip 1)
    try { & $exe @pre -c 'import sys; sys.exit(0 if (3,11) <= sys.version_info[:2] <= (3,13) else 1)' 2>$null | Out-Null } catch { continue }
    if ($LASTEXITCODE -eq 0) { return , $c }
  }
  Die 'Python 3.11-3.13 not found. Install Python 3.11 from python.org (tick "Add python.exe to PATH") or set $env:PYTHON.'
}

# 1. Python environment (reinstalled automatically when requirements.txt changes)
if (-not (Test-Path $VenvPy)) {
  $py = Find-Python
  $exe = $py[0]; $pre = @($py | Select-Object -Skip 1)
  Say "Creating virtual environment with $($py -join ' ')"
  & $exe @pre -m venv $Venv
  if ($LASTEXITCODE -ne 0) { Die 'Could not create the virtual environment.' }
}
$Req = Join-Path $Root 'backend\requirements.txt'
$Stamp = Join-Path $Venv '.eagleeye-requirements'
$Hash = (Get-FileHash -Algorithm SHA256 $Req).Hash.ToLower()
if (-not (Test-Path $Stamp) -or ((Get-Content $Stamp -Raw).Trim() -ne $Hash)) {
  Say 'Installing Python dependencies (first run downloads PyTorch; this can take several minutes)'
  & $VenvPy -m pip install --upgrade pip | Out-Null
  & $VenvPy -m pip install -r $Req
  if ($LASTEXITCODE -ne 0) { Die 'pip install failed (see the output above).' }
  Set-Content -Path $Stamp -Value $Hash
}

# 2. Model weights not stored in git (YOLOv8n COCO, EasyOCR) - same files as scripts/setup_models.sh
$Cache = Join-Path $Root 'models\cache'
$Ocr = Join-Path $Cache 'easyocr'
New-Item -ItemType Directory -Force -Path $Ocr | Out-Null
function Fetch($url, $dest) {
  if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 0)) { return }
  Say "downloading $(Split-Path -Leaf $dest)"
  for ($i = 1; $i -le 3; $i++) {
    try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile "$dest.part" -ErrorAction Stop; Move-Item -Force "$dest.part" $dest -ErrorAction Stop; return }
    catch { if ($i -eq 3) { Die "download failed: $url ($($_.Exception.Message))" }; Start-Sleep -Seconds (2 * $i) }
  }
}
function Fetch-Zip($url, $zip, $expect) {
  if (Test-Path (Join-Path $Ocr $expect)) { return }
  Fetch $url $zip
  Expand-Archive -Force -Path $zip -DestinationPath $Ocr -ErrorAction Stop
  Remove-Item -Force $zip
}
Fetch 'https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt' (Join-Path $Cache 'yolov8n.pt')
Fetch-Zip 'https://github.com/JaidedAI/EasyOCR/releases/download/pre-v1.1.6/craft_mlt_25k.zip' (Join-Path $Ocr 'craft.zip') 'craft_mlt_25k.pth'
Fetch-Zip 'https://github.com/JaidedAI/EasyOCR/releases/download/v1.3/english_g2.zip' (Join-Path $Ocr 'en.zip') 'english_g2.pth'
Say "model weights ready in $Cache"

# 3. Demo fixtures are committed; regenerate only if missing
if (-not (Test-Path (Join-Path $Root 'data\demo\fixtures.json'))) {
  Say 'Generating demonstration fixtures'
  Push-Location (Join-Path $Root 'backend'); & $VenvPy scripts/generate_demo_fixtures.py; Pop-Location
}

# 4. Web console: local Flutter build if present, else the committed prebuilt bundle
if (-not (Test-Path (Join-Path $Root 'frontend\build\web\index.html')) -and -not (Test-Path (Join-Path $Root 'frontend\prebuilt\web\index.html'))) {
  Die 'No web console build found (frontend\prebuilt\web is missing). Re-clone the repository.'
}

# 5. Start
# A port counts as busy if anything answers on it over IPv4 or IPv6 (browsers may try ::1 for "localhost").
function Test-PortBusy([int]$p) {
  foreach ($a in @(@('InterNetwork', '127.0.0.1'), @('InterNetworkV6', '::1'))) {
    try {
      $t = New-Object Net.Sockets.TcpClient([Net.Sockets.AddressFamily]::($a[0]))
      $ok = $t.ConnectAsync($a[1], $p).Wait(500)
      $t.Close()
      if ($ok) { return $true }
    } catch { }
  }
  return $false
}
if ($Port -ne 0) {
  if (Test-PortBusy $Port) { Die "Port $Port is already in use. Stop the other program or choose another: -Port 8001" }
} else {
  $Port = 8000
  while (Test-PortBusy $Port) {
    if ($Port -ge 8010) { Die 'Ports 8000-8010 are all in use. Choose a free one: -Port 9000' }
    Say "Port $Port is used by another program; trying $($Port + 1)"
    $Port++
  }
}
Say "Starting EAGLE EYE - open http://localhost:$Port in your browser   (API docs: /api/v1/docs, stop with Ctrl+C)"
Say 'Models load in the background; the first inspection on a laptop CPU takes about 1-3 minutes.'
Push-Location (Join-Path $Root 'backend')
try { & $VenvPy -m uvicorn app.main:app --host 127.0.0.1 --port $Port } finally { Pop-Location }
