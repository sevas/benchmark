# Dev-Workflow Benchmark

A self-contained Windows benchmark that measures the impact of security tools
on developer workflows.  It times three representative build pipelines — C++,
Python, and Node.js/React — and records every phase in a CSV file named after
the machine.

---

## Prerequisites

### All benchmarks

| Requirement | Details |
|---|---|
| **Windows 10/11 x64** | The benchmark is Windows-only. |
| **PowerShell 7+** | `pwsh.exe` must be on `PATH`.  [Download](https://github.com/PowerShell/PowerShell/releases) |
| **pixi.exe** | Bundled at the repository root — no separate install needed. |
| **Internet access (first run)** | Packages are downloaded on the first run and cached by pixi. Subsequent runs use the local cache. |

> **Lockfiles are committed** (`pixi.lock`, `package-lock.json`).  Exact
> package versions are therefore identical across machines; no solver is
> invoked at benchmark time.

### C++ benchmark only

| Requirement | Details |
|---|---|
| **Visual Studio 2019 or 2022** (or Build Tools) | Must include the **"Desktop development with C++"** workload so that `cl.exe` and `vcvarsall.bat` are present. [Download Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022) |

The script locates `vcvarsall.bat` automatically via `vswhere.exe`.  No manual
PATH setup is required.

---

## Repository layout

```
benchmark/
├── pixi.exe                  # Bundled pixi binary (v0.68.1, win-64)
├── run_benchmark.ps1         # Top-level runner
│
├── cpp_benchmark/            # C++ / CMake benchmark
│   ├── pixi.toml             # Boost, Eigen, fmt, spdlog, nlohmann_json, range-v3
│   ├── pixi.lock             # Pinned environment (committed)
│   ├── CMakeLists.txt
│   └── src/                  # main.cpp + 30 module_XX.cpp translation units
│
├── python_benchmark/         # Python benchmark
│   ├── pixi.toml             # Python 3.11, numpy, scipy, matplotlib, pandas, pytorch (CPU)
│   ├── pixi.lock             # Pinned environment (committed)
│   └── benchmark_imports.py
│
├── node_benchmark/           # Node.js / React benchmark
│   ├── pixi.toml             # Node.js 20+ from conda-forge
│   ├── pixi.lock             # Pinned environment (committed)
│   ├── package.json          # React 18, Vite, TypeScript, TanStack Query, Zustand, …
│   ├── package-lock.json     # Pinned npm packages (committed)
│   └── src/                  # React application source
│
└── plot_results/             # Results visualisation tool
    ├── pixi.toml             # Python + matplotlib + pandas
    ├── pixi.lock             # Pinned environment (committed)
    └── plot.py               # Grouped bar chart generator
```

---

## Running the benchmarks

Open a **PowerShell 7** session at the repository root and run:

```powershell
# Run all three benchmark suites (default)
.\run_benchmark.ps1

# Run only a specific suite
.\run_benchmark.ps1 -Benchmark cpp
.\run_benchmark.ps1 -Benchmark python
.\run_benchmark.ps1 -Benchmark node

# Tag the run with a label (e.g. to record a specific security-tool configuration)
.\run_benchmark.ps1 -Label "defender-on"
.\run_benchmark.ps1 -Label "no-av" -Benchmark cpp

# Choose cache mode: cold (always download), warm (use cached packages), or both (default)
.\run_benchmark.ps1 -CacheMode cold
.\run_benchmark.ps1 -CacheMode warm
.\run_benchmark.ps1 -CacheMode both   # default: runs cold then warm
```

When `-Label` is provided it is appended to the machine hostname with an
underscore — both in the CSV file name and in the `hostname` column.  This lets
you compare the **same machine under different conditions** in the same plot:

| Label | CSV file | hostname column |
|---|---|---|
| *(none)* | `WORKSTATION1.csv` | `WORKSTATION1` |
| `defender-on` | `WORKSTATION1_defender-on.csv` | `WORKSTATION1_defender-on` |
| `no-av` | `WORKSTATION1_no-av.csv` | `WORKSTATION1_no-av` |

The label is free-form — any string is accepted.

### Cache modes

Pixi global environments always land in `<repo>/.pixi_home/` (via `PIXI_HOME`)
so they never interfere with the user's own global pixi installation.

Use `-IsolateCache` to also redirect the conda **package cache** (`RATTLER_CACHE_DIR`)
to `<repo>/.pixi_home/cache`. The isolated cache is wiped at startup to guarantee
a clean initial state.

| Flag | Package cache used |
|---|---|
| *(default)* | System cache (`%LOCALAPPDATA%\rattler\cache`) |
| `-IsolateCache` | `<repo>/.pixi_home/cache` (wiped at startup) |

The `-CacheMode` parameter controls what happens before each env-setup phase:

| Mode | What it measures |
|---|---|
| `cold` | Wipe cache before install → full download **+** unpack |
| `warm` | Keep cache → unpack only (no download) |
| `both` | Run cold first, then warm; produces both rows in the same CSV file |

The cold-vs-warm delta isolates network/download cost from disk-IO cost.
`-IsolateCache -CacheMode both` gives the most controlled measurement.

The script requires no elevated (admin) privileges.

---

## What each benchmark measures

### C++ (`-Benchmark cpp`)

| Phase | Description |
|---|---|
| `cpp_env_setup_cold` | `pixi install --locked` with empty cache — downloads **and** unpacks all conda packages |
| `cpp_env_setup_warm` | `pixi install --locked` with populated cache — unpacks only (no download) |
| `cpp_cmake_gen` | `cmake -G Ninja …` — runs `find_package` for every dependency and generates the build system |
| `cpp_build` | `cmake --build` — parallel compilation of 31 translation units (main + 30 modules), each including ~25 heavy headers |

After the build, the script re-runs the compiler with `/showIncludes` on
`main.cpp` and appends include-file statistics to the system-info file.

### Python (`-Benchmark python`)

| Phase | Description |
|---|---|
| `py_env_setup_cold` | `pixi install --locked` with empty cache — downloads **and** unpacks Python 3.11, numpy, scipy, matplotlib, pandas, pytorch (CPU-only) |
| `py_env_setup_warm` | `pixi install --locked` with populated cache — unpacks only |
| `py_import` | Full process time for `pixi run python benchmark_imports.py` — covers pixi activation, Python interpreter startup, and importing all sub-modules of the five packages |

The script logs the number of modules loaded and a list of top-level packages
to the system-info file.

### Node.js / React (`-Benchmark node`)

| Phase | Description |
|---|---|
| `node_env_setup_cold` | `pixi install --locked` with empty cache — downloads **and** unpacks Node.js 20 via conda-forge |
| `node_env_setup_warm` | `pixi install --locked` with populated cache — unpacks only |
| `node_npm_install` | `npm ci` — installs all npm packages from `package-lock.json` into a clean `node_modules/` |
| `node_build` | `tsc --noEmit && vite build` — type-checks the project then bundles with Vite |

---

## Plotting results

The `plot_results/` directory contains a Python tool to visualise collected CSV files.

```powershell
cd plot_results

# Plot all *.csv files found in the repo root (auto-discovery)
..\pixi.exe run plot

# Or pass explicit files
..\pixi.exe run plot -- ..\MACHINE1.csv ..\MACHINE2.csv
```

The tool produces **`plot_results/results_plot.png`**: a grouped bar chart with one cluster per benchmark phase and one bar per machine.  Only the **most recent** measurement of each (machine, phase) pair is shown.  Benchmark suites (C++, Python, Node.js) are visually separated by dashed lines.

The pixi environment for the plot tool is independent and lightweight (Python + matplotlib + pandas only).

---

## Output files

Both output files are written to the **repository root** and named after the
machine (`$env:COMPUTERNAME`):

| File | Contents |
|---|---|
| `<hostname>.csv` | Timing rows — `hostname,phase,duration_seconds,timestamp` |
| `<hostname>.txt` | System configuration snapshot (CPU, RAM DIMMs, logical/physical disks, OS version) plus C++ include-file counts and Python module counts |

Each run **appends** new rows to the CSV so you can accumulate results across
multiple runs or different configurations.

### Example CSV

```csv
hostname,phase,duration_seconds,timestamp
MYPC,cpp_env_setup,12.451,2026-05-19T10:00:01
MYPC,cpp_cmake_gen,3.822,2026-05-19T10:00:14
MYPC,cpp_build,17.305,2026-05-19T10:00:32
MYPC,py_env_setup,45.012,2026-05-19T10:01:20
MYPC,py_import,11.234,2026-05-19T10:01:31
MYPC,node_env_setup,0.449,2026-05-19T10:01:32
MYPC,node_npm_install,20.149,2026-05-19T10:01:52
MYPC,node_build,5.997,2026-05-19T10:01:58
```

---

## Reproducibility

- **pixi environments** are installed from committed `pixi.lock` files
  (`--locked` flag).  The solver is not invoked; the exact same package
  versions are used on every machine.
- **npm packages** are installed with `npm ci`, which requires and respects
  `package-lock.json`.
- The pixi binary itself is bundled in the repository (`pixi.exe`) so no
  prior tooling installation is needed beyond PowerShell 7 and (for C++) a
  Visual Studio C++ workload.
