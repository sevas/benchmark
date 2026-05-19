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

    Pixi packages are cached in .pixi_home/ inside the repository root so the
    benchmark is fully isolated from the user's own pixi installation.

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

.PARAMETER CacheMode
    Controls whether the local pixi package cache is populated before each env-setup
    phase.  Three values are accepted:
      cold  — clears the cache before installing (measures download + unpack)
      warm  — keeps the cache from a previous run (measures unpack only)
      both  — runs cold then warm in sequence (default); produces two CSV rows per
              env-setup phase, named *_env_setup_cold and *_env_setup_warm.

.EXAMPLE
    .\run_benchmark.ps1
    .\run_benchmark.ps1 -Benchmark cpp
    .\run_benchmark.ps1 -Benchmark python
    .\run_benchmark.ps1 -Benchmark node
    .\run_benchmark.ps1 -Label "defender-on"
    .\run_benchmark.ps1 -Benchmark cpp -Label "no-av"
    .\run_benchmark.ps1 -CacheMode cold
    .\run_benchmark.ps1 -CacheMode warm
#>

param(
    [ValidateSet("cpp", "python", "node", "all")]
    [string]$Benchmark = "all",

    # Optional label to distinguish configuration variants on the same machine.
    # Appended to the hostname (e.g. "WORKSTATION1_av-enabled") in both the
    # CSV file name and the hostname column.
    [string]$Label = "",

    # Controls whether the pixi cache is cleared before each env-setup phase.
    #   cold  — clear cache then install  → measures full download + unpack
    #   warm  — keep cache then install   → measures unpack only
    #   both  — run cold first, then warm (default)
    [ValidateSet("cold", "warm", "both")]
    [string]$CacheMode = "both"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# In PS7, $PSScriptRoot is always the script's directory.
# $MyInvocation.MyCommand.Path can be empty in some invocation modes.
if (-not $PSScriptRoot) {
    Write-Error "PSScriptRoot is not set — please run this script as a file, not dot-sourced."
    exit 1
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Find-VcVarsAll {
    # Prefer vswhere.exe — ships with VS 2017+ installer
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = (& $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null) | Select-Object -First 1
        if ($vsPath) {
            $vsPath = $vsPath.Trim()
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

function Invoke-PixiEnvSetup {
    <#
    .SYNOPSIS
        Run a single pixi install and record the timing.
    .PARAMETER BenchDir
        Project directory that contains pixi.toml and will receive .pixi/.
    .PARAMETER PhaseBase
        Base phase name, e.g. "cpp_env_setup".  The suffix "_cold" or "_warm"
        is appended automatically based on $CacheSuffix.
    .PARAMETER CacheSuffix
        "cold" or "warm".
    .PARAMETER PixiHome
        Path to the isolated PIXI_HOME used for this benchmark run.
    #>
    param(
        [string]$BenchDir,
        [string]$PhaseBase,
        [string]$CacheSuffix,
        [string]$PixiHome
    )

    if ($CacheSuffix -eq "cold") {
        $cacheDir = Join-Path $PixiHome "cache"
        if (Test-Path $cacheDir) {
            Write-Host "  Clearing pixi cache at $cacheDir ..."
            Remove-Item -Recurse -Force $cacheDir
        }
    }

    $envDir = Join-Path $BenchDir ".pixi"
    if (Test-Path $envDir) {
        Write-Host "  Removing existing .pixi environment..."
        Remove-Item -Recurse -Force $envDir
    }

    Push-Location $BenchDir
    $elapsed = Measure-Command { cmd /c "`"$pixi`" install --locked 2>&1" | Out-Host }
    $exitCode = $LASTEXITCODE
    Pop-Location

    if ($exitCode -ne 0) { throw "pixi install failed for ${PhaseBase}_${CacheSuffix} (exit $exitCode)" }

    $phaseName = "${PhaseBase}_${CacheSuffix}"
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase $phaseName -Seconds $elapsed.TotalSeconds
    Write-Host ""
    return $elapsed
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

$scriptDir = $PSScriptRoot
$cppDir    = Join-Path $scriptDir "cpp_benchmark"
$pyDir     = Join-Path $scriptDir "python_benchmark"
$nodeDir   = Join-Path $scriptDir "node_benchmark"
Set-Location $scriptDir

# Redirect pixi's package cache to a local directory so the benchmark is
# completely isolated from the user's own pixi cache (~/.pixi/cache).
# This also makes cold-cache tests reproducible: clearing .pixi_home\cache
# guarantees a download from scratch without touching the user's packages.
$pixiHome = Join-Path $scriptDir ".pixi_home"
$env:PIXI_HOME = $pixiHome
Write-Host "  Pixi home (isolated) : $pixiHome"

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
Write-Host "  Host       : $hostname"
Write-Host "  CacheMode  : $CacheMode"
if ($Label -ne "") {
    Write-Host "  Label      : $Label"
}
Write-Host "  Output     : $csvPath"
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
$tCppEnvCold = $tCppEnvWarm = $null
$tCppCmake = $tCppBuild = $null
$tPyEnvCold  = $tPyEnvWarm = $null
$tPyImport = $null
$tNodeEnvCold = $tNodeEnvWarm = $null
$tNodeNpmInstall = $tNodeBuild = $null

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

    if ($CacheMode -in @("cold", "both")) {
        Write-Host "[C++] cpp_env_setup_cold — pixi install (empty cache)"
        $tCppEnvCold = Invoke-PixiEnvSetup -BenchDir $cppDir -PhaseBase "cpp_env_setup" -CacheSuffix "cold" -PixiHome $pixiHome
    }

    if ($CacheMode -in @("warm", "both")) {
        Write-Host "[C++] cpp_env_setup_warm — pixi install (populated cache)"
        $tCppEnvWarm = Invoke-PixiEnvSetup -BenchDir $cppDir -PhaseBase "cpp_env_setup" -CacheSuffix "warm" -PixiHome $pixiHome
    }

    Write-Host "[C++] cpp_cmake_gen — CMake configure"

    $buildDir = Join-Path $cppDir "build"
    if (Test-Path $buildDir) {
        Write-Host "  Removing existing build directory..."
        Remove-Item -Recurse -Force $buildDir
    }

    Push-Location $cppDir
    $tCppCmake  = Measure-Command { cmd /c "`"$pixi`" run cmake-gen 2>&1" | Out-Host }
    $cppCmakeExit = $LASTEXITCODE
    Pop-Location
    if ($cppCmakeExit -ne 0) { throw "cmake-gen failed (exit $cppCmakeExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "cpp_cmake_gen" -Seconds $tCppCmake.TotalSeconds
    Write-Host ""

    Write-Host "[C++] cpp_build — cmake --build"

    Push-Location $cppDir
    $tCppBuild  = Measure-Command { cmd /c "`"$pixi`" run build 2>&1" | Out-Host }
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

    if ($CacheMode -in @("cold", "both")) {
        Write-Host "[Python] py_env_setup_cold — pixi install (empty cache)"
        $tPyEnvCold = Invoke-PixiEnvSetup -BenchDir $pyDir -PhaseBase "py_env_setup" -CacheSuffix "cold" -PixiHome $pixiHome
    }

    if ($CacheMode -in @("warm", "both")) {
        Write-Host "[Python] py_env_setup_warm — pixi install (populated cache)"
        $tPyEnvWarm = Invoke-PixiEnvSetup -BenchDir $pyDir -PhaseBase "py_env_setup" -CacheSuffix "warm" -PixiHome $pixiHome
    }

    Write-Host "[Python] py_import — numpy / scipy / matplotlib / pandas / torch"

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

    if ($CacheMode -in @("cold", "both")) {
        Write-Host "[Node.js] node_env_setup_cold — pixi install (empty cache)"
        $tNodeEnvCold = Invoke-PixiEnvSetup -BenchDir $nodeDir -PhaseBase "node_env_setup" -CacheSuffix "cold" -PixiHome $pixiHome
    }

    if ($CacheMode -in @("warm", "both")) {
        Write-Host "[Node.js] node_env_setup_warm — pixi install (populated cache)"
        $tNodeEnvWarm = Invoke-PixiEnvSetup -BenchDir $nodeDir -PhaseBase "node_env_setup" -CacheSuffix "warm" -PixiHome $pixiHome
    }

    # Pixi always installs the default environment to .pixi/envs/default.
    # We use the full path to npm.cmd so no PATH configuration is needed and
    # npm.cmd's %~dp0 check resolves node.exe from the same directory reliably.
    $nodeCondaPrefix = Join-Path $nodeDir ".pixi\envs\default"
    $npm = Join-Path $nodeCondaPrefix "npm.cmd"
    if (-not (Test-Path $npm)) {
        throw "npm.cmd not found at $npm — pixi install may have failed."
    }
    Write-Host "  Using npm : $npm"

    Write-Host "[Node.js] node_npm_install — npm ci"

    # Remove node_modules to ensure a clean install every run.
    $nodeModulesDir = Join-Path $nodeDir "node_modules"
    if (Test-Path $nodeModulesDir) {
        Write-Host "  Removing existing node_modules..."
        Remove-Item -Recurse -Force $nodeModulesDir
    }

    Push-Location $nodeDir
    $tNodeNpmInstall = Measure-Command { cmd /c "`"$npm`" ci 2>&1" | Out-Host }
    $nodeNpmExit = $LASTEXITCODE
    Pop-Location
    if ($nodeNpmExit -ne 0) { throw "npm ci failed (exit $nodeNpmExit)" }
    Write-CsvRow -CsvPath $csvPath -Hostname $hostname -Phase "node_npm_install" -Seconds $tNodeNpmInstall.TotalSeconds
    Write-Host ""

    Write-Host "[Node.js] node_build — tsc + vite build"

    # Remove previous dist/ for a clean build.
    $nodeDistDir = Join-Path $nodeDir "dist"
    if (Test-Path $nodeDistDir) {
        Remove-Item -Recurse -Force $nodeDistDir
    }

    Push-Location $nodeDir
    $tNodeBuild = Measure-Command { cmd /c "`"$npm`" run build 2>&1" | Out-Host }
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
if ($null -ne $tCppEnvCold)      { Write-Host ("  cpp_env_setup_cold   : {0:F3} s" -f $tCppEnvCold.TotalSeconds) }
if ($null -ne $tCppEnvWarm)      { Write-Host ("  cpp_env_setup_warm   : {0:F3} s" -f $tCppEnvWarm.TotalSeconds) }
if ($null -ne $tCppCmake)        { Write-Host ("  cpp_cmake_gen        : {0:F3} s" -f $tCppCmake.TotalSeconds) }
if ($null -ne $tCppBuild)        { Write-Host ("  cpp_build            : {0:F3} s" -f $tCppBuild.TotalSeconds) }
if ($null -ne $tPyEnvCold)       { Write-Host ("  py_env_setup_cold    : {0:F3} s" -f $tPyEnvCold.TotalSeconds) }
if ($null -ne $tPyEnvWarm)       { Write-Host ("  py_env_setup_warm    : {0:F3} s" -f $tPyEnvWarm.TotalSeconds) }
if ($null -ne $tPyImport)        { Write-Host ("  py_import            : {0:F3} s" -f $tPyImport.TotalSeconds) }
if ($null -ne $tNodeEnvCold)     { Write-Host ("  node_env_setup_cold  : {0:F3} s" -f $tNodeEnvCold.TotalSeconds) }
if ($null -ne $tNodeEnvWarm)     { Write-Host ("  node_env_setup_warm  : {0:F3} s" -f $tNodeEnvWarm.TotalSeconds) }
if ($null -ne $tNodeNpmInstall)  { Write-Host ("  node_npm_install     : {0:F3} s" -f $tNodeNpmInstall.TotalSeconds) }
if ($null -ne $tNodeBuild)       { Write-Host ("  node_build           : {0:F3} s" -f $tNodeBuild.TotalSeconds) }
Write-Host "========================================"
