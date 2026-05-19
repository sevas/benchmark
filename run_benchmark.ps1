<#
.SYNOPSIS
    Dev-workflow benchmark runner — C++, Python, and Node.js/React.

.DESCRIPTION
    Measures key phases of developer workflows:

    C++ phases (--Benchmark cpp or all):
      cpp_env_setup  — pixi install (environment extraction)
      cpp_cmake_gen  — CMake configuration (find_package for all deps)
      cpp_build      — Full parallel compilation from scratch

    Python phases (--Benchmark python or all):
      py_env_setup   — pixi install (Python + numpy/scipy/matplotlib/pandas/torch)
      py_import      — Full process time: pixi run + Python startup + heavy imports

    Node.js/React phases (--Benchmark node or all):
      node_env_setup      — pixi install (Node.js via conda-forge)
      node_npm_install    — npm ci (install all packages from package-lock.json)
      node_build          — tsc --noEmit && vite build

    Results are appended to <hostname>.csv at the script root.
    A system-info text file is also written/updated at <hostname>.txt.

    For C++, MSVC (cl.exe) must be installed; vcvarsall.bat is located
    automatically via vswhere.exe or well-known Visual Studio install paths.

.PARAMETER Benchmark
    Which suite to run. Accepted values: cpp, python, node, all (default).

.PARAMETER Label
    Optional free-form label describing this run's configuration (e.g. "defender-on",
    "no-av", "baseline"). When provided it is appended to the hostname with an
    underscore, both in the CSV file name and in the hostname column so different
    configurations of the same machine appear as distinct series in the plots.
    Example: on WORKSTATION1 with -Label "av-enabled" → file WORKSTATION1_av-enabled.csv,
    hostname column "WORKSTATION1_av-enabled".

.EXAMPLE
    .\run_benchmark.ps1
    .\run_benchmark.ps1 -Benchmark cpp
    .\run_benchmark.ps1 -Benchmark python
    .\run_benchmark.ps1 -Benchmark node
    .\run_benchmark.ps1 -Label "defender-on"
    .\run_benchmark.ps1 -Benchmark cpp -Label "no-av"
#>

param(
    [ValidateSet("cpp", "python", "node", "all")]
    [string]$Benchmark = "all",

    # Optional label to distinguish configuration variants on the same machine.
    # Appended to the hostname (e.g. "WORKSTATION1_av-enabled") in both the
    # CSV file name and the hostname column.
    [string]$Label = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Find-VcVarsAll {
    # Prefer vswhere.exe — ships with VS 2017+ installer
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null
        if ($vsPath) {
            $candidate = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    # Fallback: well-known paths for VS 2022 and VS 2019
    $fallbacks = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
    )
    foreach ($path in $fallbacks) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Set-MsvcEnvironment {
    param([string]$VcVarsPath, [string]$Arch = "x64")
    Write-Host "  Activating MSVC via: $VcVarsPath ($Arch)"
    $lines = cmd /c "`"$VcVarsPath`" $Arch 2>&1 && set" 2>&1
    foreach ($line in $lines) {
        if ($line -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
        }
    }
}

function Write-CsvRow {
    param([string]$CsvPath, [string]$Hostname, [string]$Phase, [double]$Seconds)
    $ts = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    $row = "$Hostname,$Phase,$([math]::Round($Seconds, 3)),$ts"
    Add-Content -Path $CsvPath -Value $row
    Write-Host "  Recorded: $row"
}

function Measure-Includes {
    param([string]$ScriptDir, [string]$InfoPath)

    # Read the compile command for main.cpp from the build produced in phase 2/3.
    # cmake-gen exports compile_commands.json (Ninja + EXPORT_COMPILE_COMMANDS=ON).
    $ccJson = Join-Path $ScriptDir "build\compile_commands.json"
    if (-not (Test-Path $ccJson)) {
        Write-Warning "compile_commands.json not found — skipping include analysis."
        return
    }

    $entries  = Get-Content $ccJson -Raw | ConvertFrom-Json
    $entry    = $entries | Where-Object { $_.file -like "*main.cpp" } | Select-Object -First 1
    if (-not $entry) {
        Write-Warning "main.cpp not found in compile_commands.json — skipping include analysis."
        return
    }

    # Append /showIncludes to the exact command cmake used, run from the build dir.
    $cmd     = $entry.command + " /showIncludes"
    $buildDir = $entry.directory

    Write-Host "  Running compiler with /showIncludes..."
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        # Invoke via cmd so PowerShell does not wrap stderr as ErrorRecord objects.
        # The current process already has MSVC env vars (set by vcvarsall earlier),
        # and cmd.exe inherits the process environment block.
        Push-Location $buildDir
        cmd /c "$cmd > `"$tmpFile`" 2>&1"
        $exitCode = $LASTEXITCODE
        Pop-Location

        if ($exitCode -ne 0) {
            Write-Warning "Compiler exited $exitCode during include analysis — counts may be partial."
        }

        $rawOutput    = Get-Content $tmpFile -ErrorAction SilentlyContinue
        $includePaths = $rawOutput |
            Where-Object { $_ -match '^Note: including file:\s+(.+)$' } |
            ForEach-Object { $Matches[1].Trim() }

        $totalIncludes  = $includePaths.Count
        $uniqueIncludes = ($includePaths | Sort-Object -Unique).Count

        Write-Host "  Total include directives : $totalIncludes"
        Write-Host "  Unique files included    : $uniqueIncludes"

        $section = @(
            "",
            "=== Include file analysis (src/main.cpp) ===",
            "  Total include directives : $totalIncludes",
            "  Unique files included    : $uniqueIncludes"
        )
        Add-Content -Path $InfoPath -Value $section -Encoding UTF8
    }
    finally {
        Remove-Item -Force $tmpFile -ErrorAction SilentlyContinue
    }
}

function Write-SystemInfo {
    param([string]$InfoPath, [string]$Hostname)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("System Information — $Hostname")
    $lines.Add("Generated : $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')")
    $lines.Add("")

    # CPU
    $lines.Add("=== CPU ===")
    $cpus = Get-CimInstance Win32_Processor
    foreach ($cpu in $cpus) {
        $lines.Add("  Name             : $($cpu.Name.Trim())")
        $lines.Add("  Cores (physical) : $($cpu.NumberOfCores)")
        $lines.Add("  Logical procs    : $($cpu.NumberOfLogicalProcessors)")
        $lines.Add("  Max clock (MHz)  : $($cpu.MaxClockSpeed)")
        $lines.Add("  Socket           : $($cpu.SocketDesignation)")
    }
    $lines.Add("")

    # RAM
    $lines.Add("=== RAM ===")
    $cs = Get-CimInstance Win32_ComputerSystem
    $totalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $lines.Add("  Total physical   : $totalGB GB")
    $dimms = Get-CimInstance Win32_PhysicalMemory
    foreach ($d in $dimms) {
        $sizeGB = [math]::Round($d.Capacity / 1GB, 0)
        $lines.Add("  DIMM $($d.DeviceLocator): $sizeGB GB  $($d.Speed) MHz  $($d.MemoryType -replace '^0$','?')")
    }
    $lines.Add("")

    # Storage
    $lines.Add("=== Storage (logical disks) ===")
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($d in $disks) {
        $totalGB = [math]::Round($d.Size / 1GB, 1)
        $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
        $lines.Add("  $($d.DeviceID)  total=$totalGB GB  free=$freeGB GB  fs=$($d.FileSystem)")
    }
    $lines.Add("")

    # Physical disk model / type
    $lines.Add("=== Physical disks ===")
    $physDisks = Get-PhysicalDisk | Sort-Object DeviceId
    foreach ($pd in $physDisks) {
        $sizeGB = [math]::Round($pd.Size / 1GB, 1)
        $lines.Add("  [$($pd.DeviceId)] $($pd.FriendlyName)  $($pd.MediaType)  $sizeGB GB")
    }
    $lines.Add("")

    # OS
    $lines.Add("=== OS ===")
    $os = Get-CimInstance Win32_OperatingSystem
    $lines.Add("  Caption    : $($os.Caption)")
    $lines.Add("  Version    : $($os.Version)")
    $lines.Add("  Build      : $($os.BuildNumber)")
    $lines.Add("  Arch       : $($os.OSArchitecture)")

    $lines | Set-Content -Path $InfoPath -Encoding UTF8
    Write-Host "  System info written to: $InfoPath"
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cppDir    = Join-Path $scriptDir "cpp_benchmark"
$pyDir     = Join-Path $scriptDir "python_benchmark"
$nodeDir   = Join-Path $scriptDir "node_benchmark"
Set-Location $scriptDir

# Use the bundled pixi binary so the benchmark is self-contained.
$pixi = Join-Path $scriptDir "pixi.exe"
if (-not (Test-Path $pixi)) {
    Write-Error "pixi.exe not found in $scriptDir. Please ensure the repository is complete."
    exit 1
}
if ($Benchmark -in @("cpp", "all") -and -not (Test-Path $cppDir)) {
    Write-Error "cpp_benchmark/ subfolder not found in $scriptDir."
    exit 1
}
if ($Benchmark -in @("python", "all") -and -not (Test-Path $pyDir)) {
    Write-Error "python_benchmark/ subfolder not found in $scriptDir."
    exit 1
}
if ($Benchmark -in @("node", "all") -and -not (Test-Path $nodeDir)) {
    Write-Error "node_benchmark/ subfolder not found in $scriptDir."
    exit 1
}

$hostname = $env:COMPUTERNAME
if ($Label -ne "") {
    $hostname = "${hostname}_${Label}"
}
$csvPath  = Join-Path $scriptDir "$hostname.csv"
$infoPath = Join-Path $scriptDir "$hostname.txt"

Write-Host ""
Write-Host "========================================"
Write-Host "  Dev-Workflow Benchmark  [$Benchmark]"
Write-Host "  Host   : $hostname"
if ($Label -ne "") {
    Write-Host "  Label  : $Label"
}
Write-Host "  Output : $csvPath"
Write-Host "========================================"
Write-Host ""

# Create CSV with header if it doesn't exist yet
if (-not (Test-Path $csvPath)) {
    "hostname,phase,duration_seconds,timestamp" | Set-Content -Path $csvPath
}

# Collect and write system configuration
Write-Host "[*] Collecting system information..."
Write-SystemInfo -InfoPath $infoPath -Hostname $hostname
Write-Host ""

# Initialize all timing vars to $null so the summary can test what actually ran.
$tCppEnv = $tCppCmake = $tCppBuild = $null
$tPyEnv  = $tPyImport = $null
$tNodeEnv = $tNodeNpmInstall = $tNodeBuild = $null

# ---------------------------------------------------------------------------
# MSVC environment (only needed for C++ benchmark)
# ---------------------------------------------------------------------------

if ($Benchmark -in @("cpp", "all")) {
    Write-Host "[*] Locating MSVC toolchain..."
    $vcvars = Find-VcVarsAll
    if (-not $vcvars) {
        Write-Error "Could not find vcvarsall.bat. Please install Visual Studio or Build Tools with the C++ workload."
        exit 1
    }
    Set-MsvcEnvironment -VcVarsPath $vcvars -Arch "x64"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# C++ benchmark
# ---------------------------------------------------------------------------

if ($Benchmark -in @("cpp", "all")) {
    Write-Host "[C++] 1/3 cpp_env_setup — pixi install"

    $pixiEnvDir = Join-Path $cppDir ".pixi"
    if (Test-Path $pixiEnvDir) {
        Write-Host "  Removing existing .pixi environment..."
        Remove-Item -Recurse -Force $pixiEnvDir
    }

    Push-Location $cppDir
    $tCppEnv  = Measure-Command { & $pixi install --locked 2>&1 | Out-Host }
    $cppEnvExit = $LASTEXITCODE
    Pop-Location
    if ($cppEnvExit -ne 0) { throw "pixi install failed (exit $cppEnvExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "cpp_env_setup" -Seconds $tCppEnv.TotalSeconds
    Write-Host ""

    Write-Host "[C++] 2/3 cpp_cmake_gen — CMake configure"

    $buildDir = Join-Path $cppDir "build"
    if (Test-Path $buildDir) {
        Write-Host "  Removing existing build directory..."
        Remove-Item -Recurse -Force $buildDir
    }

    Push-Location $cppDir
    $tCppCmake  = Measure-Command { & $pixi run cmake-gen 2>&1 | Out-Host }
    $cppCmakeExit = $LASTEXITCODE
    Pop-Location
    if ($cppCmakeExit -ne 0) { throw "cmake-gen failed (exit $cppCmakeExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "cpp_cmake_gen" -Seconds $tCppCmake.TotalSeconds
    Write-Host ""

    Write-Host "[C++] 3/3 cpp_build — cmake --build"

    Push-Location $cppDir
    $tCppBuild  = Measure-Command { & $pixi run build 2>&1 | Out-Host }
    $cppBuildExit = $LASTEXITCODE
    Pop-Location
    if ($cppBuildExit -ne 0) { throw "build failed (exit $cppBuildExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "cpp_build" -Seconds $tCppBuild.TotalSeconds
    Write-Host ""

    Write-Host "[*] Counting included files..."
    Measure-Includes -ScriptDir $cppDir -InfoPath $infoPath
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Python benchmark
# ---------------------------------------------------------------------------

if ($Benchmark -in @("python", "all")) {
    Write-Host "[Python] 1/2 py_env_setup — pixi install"

    $pyEnvDir = Join-Path $pyDir ".pixi"
    if (Test-Path $pyEnvDir) {
        Write-Host "  Removing existing .pixi environment..."
        Remove-Item -Recurse -Force $pyEnvDir
    }

    Push-Location $pyDir
    $tPyEnv  = Measure-Command { & $pixi install --locked 2>&1 | Out-Host }
    $pyEnvExit = $LASTEXITCODE
    Pop-Location
    if ($pyEnvExit -ne 0) { throw "Python pixi install failed (exit $pyEnvExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "py_env_setup" -Seconds $tPyEnv.TotalSeconds
    Write-Host ""

    Write-Host "[Python] 2/2 py_import — numpy / scipy / matplotlib / pandas / torch"

    # Agg backend: suppresses font-cache/GUI initialisation so timings reflect
    # module loading rather than display-system warm-up.
    $env:MPLBACKEND = "Agg"
    $tmpPy = [System.IO.Path]::GetTempFileName()
    try {
        Push-Location $pyDir
        $tPyImport = Measure-Command {
            cmd /c "`"$pixi`" run run-benchmark > `"$tmpPy`" 2>&1"
        }
        $pyImportExit = $LASTEXITCODE
        Pop-Location

        if ($pyImportExit -ne 0) { throw "Python benchmark failed (exit $pyImportExit)" }

        $pyOut = Get-Content $tmpPy -ErrorAction SilentlyContinue
        $pyOut | Out-Host

        Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "py_import" -Seconds $tPyImport.TotalSeconds

        # Append in-process details to the system info file.
        $inProcLine   = $pyOut | Where-Object { $_ -match '^import_time_seconds=' }  | Select-Object -First 1
        $modulesLine  = $pyOut | Where-Object { $_ -match '^modules_loaded=' }       | Select-Object -First 1
        $topLine      = $pyOut | Where-Object { $_ -match '^top_level_packages=' }   | Select-Object -First 1
        $pkgListLine  = $pyOut | Where-Object { $_ -match '^packages_list=' }        | Select-Object -First 1

        $section = @("", "=== Python module analysis ===")
        if ($inProcLine)  { $section += "  In-process import time  : $(($inProcLine  -replace 'import_time_seconds=','').Trim()) s" }
        if ($modulesLine) { $section += "  Total modules loaded    : $(($modulesLine -replace 'modules_loaded=','').Trim())" }
        if ($topLine)     { $section += "  Top-level packages      : $(($topLine     -replace 'top_level_packages=','').Trim())" }
        $section += "  Full process time       : $([math]::Round($tPyImport.TotalSeconds, 3)) s  (pixi activation + Python startup + imports)"
        if ($pkgListLine) {
            $pkgs = (($pkgListLine -replace 'packages_list=','').Trim()) -split ','
            $section += ""
            $section += "  Packages:"
            foreach ($pkg in $pkgs) { $section += "    $pkg" }
        }

        Add-Content -Path $infoPath -Value $section -Encoding UTF8

        if ($modulesLine) { Write-Host "  Total modules loaded   : $(($modulesLine -replace 'modules_loaded=','').Trim())" }
        if ($topLine)     { Write-Host "  Top-level packages     : $(($topLine     -replace 'top_level_packages=','').Trim())" }
    }
    finally {
        Remove-Item -Force $tmpPy -ErrorAction SilentlyContinue
        [System.Environment]::SetEnvironmentVariable("MPLBACKEND", $null, "Process")
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Node.js / React benchmark
# ---------------------------------------------------------------------------

if ($Benchmark -in @("node", "all")) {
    Write-Host "[Node.js] 1/3 node_env_setup — pixi install"

    $nodePixiEnvDir = Join-Path $nodeDir ".pixi"
    if (Test-Path $nodePixiEnvDir) {
        Write-Host "  Removing existing .pixi environment..."
        Remove-Item -Recurse -Force $nodePixiEnvDir
    }

    Push-Location $nodeDir
    $tNodeEnv = Measure-Command { & $pixi install --locked 2>&1 | Out-Host }
    $nodeEnvExit = $LASTEXITCODE
    Pop-Location
    if ($nodeEnvExit -ne 0) { throw "Node.js pixi install failed (exit $nodeEnvExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "node_env_setup" -Seconds $tNodeEnv.TotalSeconds
    Write-Host ""

    # Pixi always installs the default environment to .pixi/envs/default.
    # We use the full path to npm.cmd so no PATH configuration is needed and
    # npm.cmd's %~dp0 check resolves node.exe from the same directory reliably.
    $nodeCondaPrefix = Join-Path $nodeDir ".pixi\envs\default"
    $npm = Join-Path $nodeCondaPrefix "npm.cmd"
    if (-not (Test-Path $npm)) {
        throw "npm.cmd not found at $npm — pixi install may have failed."
    }
    Write-Host "  Using npm : $npm"

    Write-Host "[Node.js] 2/3 node_npm_install — npm ci"

    # Remove node_modules to ensure a clean install every run.
    $nodeModulesDir = Join-Path $nodeDir "node_modules"
    if (Test-Path $nodeModulesDir) {
        Write-Host "  Removing existing node_modules..."
        Remove-Item -Recurse -Force $nodeModulesDir
    }

    Push-Location $nodeDir
    $tNodeNpmInstall = Measure-Command { & $npm ci 2>&1 | Out-Host }
    $nodeNpmExit = $LASTEXITCODE
    Pop-Location
    if ($nodeNpmExit -ne 0) { throw "npm ci failed (exit $nodeNpmExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "node_npm_install" -Seconds $tNodeNpmInstall.TotalSeconds
    Write-Host ""

    Write-Host "[Node.js] 3/3 node_build — tsc + vite build"

    # Remove previous dist/ for a clean build.
    $nodeDistDir = Join-Path $nodeDir "dist"
    if (Test-Path $nodeDistDir) {
        Remove-Item -Recurse -Force $nodeDistDir
    }

    Push-Location $nodeDir
    $tNodeBuild = Measure-Command { & $npm run build 2>&1 | Out-Host }
    $nodeBuildExit = $LASTEXITCODE
    Pop-Location
    if ($nodeBuildExit -ne 0) { throw "npm run build failed (exit $nodeBuildExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "node_build" -Seconds $tNodeBuild.TotalSeconds
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host "========================================"
Write-Host "  Results written to  : $csvPath"
Write-Host "  System info written : $infoPath"
Write-Host "----------------------------------------"
if ($null -ne $tCppEnv)          { Write-Host ("  cpp_env_setup      : {0:F3} s" -f $tCppEnv.TotalSeconds) }
if ($null -ne $tCppCmake)        { Write-Host ("  cpp_cmake_gen      : {0:F3} s" -f $tCppCmake.TotalSeconds) }
if ($null -ne $tCppBuild)        { Write-Host ("  cpp_build          : {0:F3} s" -f $tCppBuild.TotalSeconds) }
if ($null -ne $tPyEnv)           { Write-Host ("  py_env_setup       : {0:F3} s" -f $tPyEnv.TotalSeconds) }
if ($null -ne $tPyImport)        { Write-Host ("  py_import          : {0:F3} s" -f $tPyImport.TotalSeconds) }
if ($null -ne $tNodeEnv)         { Write-Host ("  node_env_setup     : {0:F3} s" -f $tNodeEnv.TotalSeconds) }
if ($null -ne $tNodeNpmInstall)  { Write-Host ("  node_npm_install   : {0:F3} s" -f $tNodeNpmInstall.TotalSeconds) }
if ($null -ne $tNodeBuild)       { Write-Host ("  node_build         : {0:F3} s" -f $tNodeBuild.TotalSeconds) }
Write-Host "========================================"
