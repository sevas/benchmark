# Agent instructions — dev-workflow benchmark

This file contains conventions and hard-won lessons for anyone (human or AI)
editing this repository.  Read it before making changes.

---

## Purpose

This benchmark measures the impact of security tooling (AV, EDR, etc.) on
developer workflows on Windows.  It times three pipelines — C++, Python, and
Node.js/React — using **pixi** for environment management.  All environments
are pinned via committed lockfiles so results are reproducible across machines.

---

## Architecture

```
run_benchmark.ps1          ← single orchestration script, Windows PowerShell 7
cpp_benchmark/             ← CMake + MSVC + conda-forge C++ deps
python_benchmark/          ← CPython + heavy scientific imports
node_benchmark/            ← Node.js 20 + Vite + React TypeScript app
pixi.exe                   ← bundled pixi binary (win-64); never remove
```

`run_benchmark.ps1` accepts `-Benchmark cpp|python|node|all` (default `all`), an optional free-form `-Label <string>`, and an optional `-CacheMode cold|warm|both` (default `both`).  When a label is given it is appended to the hostname with an underscore in both the CSV filename and the `hostname` column (e.g. `WORKSTATION1_defender-on`), enabling same-machine / different-configuration comparisons in the plot tool.

### Pixi cache isolation

The script sets `$env:PIXI_HOME = "<repo>/.pixi_home"` before any pixi call,
redirecting pixi's entire home (cache + global envs) away from the user's own
pixi installation.  This directory is **excluded from git** (see `.gitignore`).

- **Cold cache**: delete `$pixiHome/cache` before `pixi install` → forces full download + unpack.
- **Warm cache**: keep `$pixiHome/cache`, delete only the local `.pixi` env dir → measures unpack only.
- **Phase names**: `cpp_env_setup_cold`, `cpp_env_setup_warm` (and same for `py_`, `node_`).
  Legacy bare names (`cpp_env_setup` etc.) appear only in old CSV files (e.g. SIGIL.csv).

The `Invoke-PixiEnvSetup` helper function handles clearing + timing + CSV recording for both modes.
Output files (`<hostname>.csv`, `<hostname>.txt`) are written to the repo root.

---

## Critical invariants — do not break these

### pixi

- **Always pass `--locked`** to every `pixi install` call.  This ensures
  reproducibility.  If you add/change a dependency you MUST regenerate the
  lockfile (`pixi install` without `--locked`) and commit the new `pixi.lock`.
- **`[workspace]`** is the correct top-level section (not `[project]`).  pixi
  v0.68.1+ requires this.
- Each benchmark sub-directory has its **own `pixi.toml` / `pixi.lock`** and
  must be invoked with `Push-Location <dir>` / `Pop-Location` around every
  `pixi` call, because pixi resolves `pixi.toml` from the working directory.

### Python benchmark

- Channels **must** be `["pytorch", "conda-forge"]` in that order, with
  `cpuonly = "*"` as a dependency.  Using conda-forge alone pulls a CUDA
  pytorch build (multi-GB).
- `benchmark_imports.py` must print exactly four parseable lines to stdout:
  `import_time_seconds=`, `modules_loaded=`, `top_level_packages=`,
  `packages_list=`.  The PS1 script parses these by exact prefix match.
- Run the script via `cmd /c "pixi run run-benchmark > tmpfile 2>&1"` and
  read the temp file, not via `& $pixi run ... | Out-Host`.  PowerShell wraps
  stderr as `ErrorRecord` objects when `$ErrorActionPreference = "Stop"`, which
  terminates the script before the exit code is checked.

### C++ benchmark

- `abseil-cpp` on conda-forge win-64 only has version `20220623.0`.  Any
  `>=20240116` constraint is unsolvable.  Use `abseil-cpp = "*"`.
- `CMakeLists.txt` uses `CMAKE_EXPORT_COMPILE_COMMANDS=ON` (Ninja generator).
  `Measure-Includes` depends on `build/compile_commands.json` being present.
- MSVC environment variables are set once at the top of the script via
  `Set-MsvcEnvironment`.  Child `cmd /c` processes inherit the process
  environment block — no need to re-activate per command.
- range-v3 accumulate header: `range/v3/numeric/accumulate.hpp` (NOT
  `algorithm/`).
- Eigen QR: use `matrixQR()`, not `matrixQ()`.
- Boost CMake target for header-only use: `Boost::headers`.

### Node.js benchmark

- Uses `npm ci` (not `npm install`) for the benchmark phases.  This requires a
  committed `package-lock.json`.  If you add/change npm deps, run `npm install`
  locally to regenerate `package-lock.json`, then commit it.
- **Do NOT call npm via `pixi run`** or via PATH in the benchmark.  After
  `pixi install --locked`, the PS1 script constructs the full path to `npm.cmd`
  directly as `$nodeDir\.pixi\envs\default\npm.cmd` (pixi always places the
  default environment there).  Calling `& $npm ci` with the full path means
  `npm.cmd`'s own `%~dp0\node.exe` check resolves correctly regardless of PATH,
  eliminating all child-process PATH issues.
- **Do NOT use `--scripts-prepend-node-path=true` as a CLI arg.**  npm 11
  splits `--flag=value` into separate argv tokens; `true` is then treated as a
  workspace specifier, causing `npm ci` to exit 1 immediately.
- TypeScript is strict (`"strict": true`).  `useQuery().data` may be
  `undefined`; handle it or use `initialData`.  Type axios responses
  explicitly.
- Lodash: use named imports (`import { range } from 'lodash'`).
- Tailwind is present as an installed package but PostCSS is not wired up.
  Do not add `tailwind.config.js` or `postcss.config.js` unless you intend to
  fully configure the CSS pipeline.

---

## Adding a new benchmark

1. Create `<name>_benchmark/` with its own `pixi.toml`.
2. Add `"<name>"` to the `ValidateSet` in `run_benchmark.ps1`.
3. Add `$<name>Dir = Join-Path $scriptDir "<name>_benchmark"` and a guard
   checking the directory exists.
4. Initialize timing variables to `$null` before the benchmark blocks.
5. Follow the `Push-Location / Measure-Command / Pop-Location / Write-CsvRow`
   pattern used by the existing blocks.
6. Add the new timings to the summary section at the bottom.
7. Run `pixi install` (without `--locked`) in the new sub-directory to
   generate `pixi.lock`, then commit it.
8. Update `README.md`.

---

## CSV format

```
hostname,phase,duration_seconds,timestamp
```

- Phase names follow the convention `<suite>_<step>[_cold|_warm]`, e.g.
  `cpp_env_setup_cold`, `cpp_build`, `py_import`, `node_npm_install`.
  Cold/warm suffixes are used for env-setup phases only.
- Each run **appends** rows — do not truncate the CSV.
- The CSV header row is written only once (if the file does not exist yet).

---

## PowerShell conventions in `run_benchmark.ps1`

- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = "Stop"` are
  set at the top.  Every external command that can fail must have its exit
  code checked explicitly after `Measure-Command` returns (capture into a
  `$xxxExit` variable, then `if ($xxxExit -ne 0) { throw … }`).
- Use `& $pixi run <task> 2>&1 | Out-Host` for commands whose output should
  be visible in the terminal.
- Use `cmd /c "..." > tmpfile 2>&1` + read temp file when you need to capture
  stdout lines for parsing (avoids the ErrorRecord wrapping issue).
- Prefer `Push-Location` / `Pop-Location` over `Set-Location` so the CWD is
  always restored even if an error is thrown.
- All timing variables are initialized to `$null` before any benchmark block
  so the null-guard in the summary (`if ($null -ne $tXxx)`) works correctly
  when only a subset of benchmarks runs.
