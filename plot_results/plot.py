"""
plot.py — Visualise benchmark timings from one or more CSV files.

Usage
-----
  pixi run plot                        # reads *.csv from the parent directory
  pixi run plot -- A.csv B.csv ...     # explicit list of CSV files

Each CSV must follow the benchmark schema:
  hostname,phase,duration_seconds,timestamp

For every (hostname, phase) pair the **most recent** measurement is used.

Output
------
  results_plot.png  — saved next to this script
  (the plot is also shown in an interactive window when a display is available)
"""

import sys
import glob
import pathlib
from typing import Optional

import pandas as pd
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

# ---------------------------------------------------------------------------
# Phase catalogue — defines display order and benchmark group labels.
# Unknown phases found in the data are appended at the end.
# ---------------------------------------------------------------------------

PHASE_ORDER = [
    # C++ suite — cold/warm variants first, then legacy bare name
    "cpp_env_setup_cold",
    "cpp_env_setup_warm",
    "cpp_env_setup",        # legacy (no cache suffix)
    "cpp_cmake_gen",
    "cpp_build",
    # Python suite
    "py_env_setup_cold",
    "py_env_setup_warm",
    "py_env_setup",         # legacy
    "py_import",
    # Node.js suite
    "node_env_setup_cold",
    "node_env_setup_warm",
    "node_env_setup",       # legacy
    "node_npm_install",
    "node_build",
]

PHASE_LABELS = {
    "cpp_env_setup_cold":  "C++ env\n(cold)",
    "cpp_env_setup_warm":  "C++ env\n(warm)",
    "cpp_env_setup":       "C++ env\nsetup",
    "cpp_cmake_gen":       "C++ cmake\ngen",
    "cpp_build":           "C++ build",
    "py_env_setup_cold":   "Py env\n(cold)",
    "py_env_setup_warm":   "Py env\n(warm)",
    "py_env_setup":        "Python env\nsetup",
    "py_import":           "Python\nimport",
    "node_env_setup_cold": "Node env\n(cold)",
    "node_env_setup_warm": "Node env\n(warm)",
    "node_env_setup":      "Node env\nsetup",
    "node_npm_install":    "npm ci",
    "node_build":          "vite build",
}

# Vertical separator (None) marks where one benchmark suite ends and the next begins.
GROUP_SEPARATORS_AFTER = {"cpp_build", "py_import"}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_csvs(paths: list[str]) -> pd.DataFrame:
    frames = []
    for p in paths:
        try:
            df = pd.read_csv(
                p,
                names=["hostname", "phase", "duration_seconds", "timestamp"],
                parse_dates=["timestamp"],
                date_format="ISO8601",
                comment="#",
            )
            # Drop header row if it slipped through (some files have it)
            df = df[df["hostname"] != "hostname"]
            df["duration_seconds"] = pd.to_numeric(df["duration_seconds"], errors="coerce")
            frames.append(df)
        except Exception as exc:
            print(f"  Warning: could not read {p}: {exc}")
    if not frames:
        raise SystemExit("No valid CSV data found.")
    return pd.concat(frames, ignore_index=True)


def latest_per_host_phase(df: pd.DataFrame) -> pd.DataFrame:
    """Keep the single most-recent measurement for each (hostname, phase) pair."""
    df = df.sort_values("timestamp")
    return (
        df.groupby(["hostname", "phase"], sort=False)
        .last()
        .reset_index()
    )


def ordered_phases(df: pd.DataFrame) -> list[str]:
    """Return phases in catalogue order, with any unknown ones appended."""
    known = [p for p in PHASE_ORDER if p in df["phase"].unique()]
    extras = [p for p in df["phase"].unique() if p not in PHASE_ORDER]
    return known + sorted(extras)


# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------

def plot(df: pd.DataFrame, out_path: pathlib.Path) -> None:
    phases = ordered_phases(df)
    hosts  = sorted(df["hostname"].unique())
    n_phases = len(phases)
    n_hosts  = len(hosts)

    # Colour palette — qualitative, up to ~12 hosts
    cmap = plt.get_cmap("tab10" if n_hosts <= 10 else "tab20")
    host_colours = {h: cmap(i / max(n_hosts - 1, 1)) for i, h in enumerate(hosts)}

    bar_width   = 0.7 / max(n_hosts, 1)
    group_gap   = 1.4          # distance between phase-group centres
    sep_extra   = 0.4          # extra gap after a benchmark-suite boundary

    # Build x-centres for each phase group, inserting extra whitespace at suite
    # boundaries so the clusters are visually separated.
    centres: list[float] = []
    x = 0.0
    for phase in phases:
        centres.append(x)
        gap = group_gap + (sep_extra if phase in GROUP_SEPARATORS_AFTER else 0.0)
        x += gap

    fig, ax = plt.subplots(figsize=(max(10, n_phases * 1.4 + 2), 6))

    # Draw bars
    for host_idx, host in enumerate(hosts):
        host_df = df[df["hostname"] == host].set_index("phase")
        offsets = (np.arange(n_hosts) - (n_hosts - 1) / 2) * bar_width
        x_pos   = [c + offsets[host_idx] for c in centres]

        for i, phase in enumerate(phases):
            if phase not in host_df.index:
                continue
            value = host_df.loc[phase, "duration_seconds"]
            bar = ax.bar(
                x_pos[i],
                value,
                width=bar_width * 0.92,
                color=host_colours[host],
                label=host if i == 0 else "_nolegend_",
                zorder=3,
            )
            # Value label on top of bar
            ax.text(
                x_pos[i],
                value + 0.02 * ax.get_ylim()[1],
                f"{value:.1f}s",
                ha="center",
                va="bottom",
                fontsize=7,
                color="dimgray",
            )

    # After all bars are drawn, re-compute ylim and re-place value labels
    ax.relim()
    ax.autoscale_view()
    y_top = ax.get_ylim()[1]
    # Clear and redraw value labels now that ylim is stable
    for txt in ax.texts:
        txt.remove()
    for host_idx, host in enumerate(hosts):
        host_df = df[df["hostname"] == host].set_index("phase")
        offsets = (np.arange(n_hosts) - (n_hosts - 1) / 2) * bar_width
        x_pos   = [c + offsets[host_idx] for c in centres]
        for i, phase in enumerate(phases):
            if phase not in host_df.index:
                continue
            value = host_df.loc[phase, "duration_seconds"]
            ax.text(
                x_pos[i],
                value + y_top * 0.015,
                f"{value:.1f}s",
                ha="center", va="bottom", fontsize=7, color="dimgray",
            )

    # Suite boundary separators (vertical dashed lines)
    for i, phase in enumerate(phases):
        if phase in GROUP_SEPARATORS_AFTER and i < n_phases - 1:
            sep_x = (centres[i] + centres[i + 1]) / 2
            ax.axvline(sep_x, color="lightgray", linestyle="--", linewidth=1, zorder=1)

    # X-axis ticks
    ax.set_xticks(centres)
    ax.set_xticklabels(
        [PHASE_LABELS.get(p, p.replace("_", "\n")) for p in phases],
        fontsize=9,
    )
    ax.set_xlim(centres[0] - group_gap * 0.6, centres[-1] + group_gap * 0.6)
    ax.set_ylim(0, y_top * 1.12)

    # Suite labels above the plot
    suite_groups: dict[str, list[int]] = {}
    for i, phase in enumerate(phases):
        suite = phase.split("_")[0]
        suite_groups.setdefault(suite, []).append(i)
    suite_display = {"cpp": "C++", "py": "Python", "node": "Node.js / React"}
    for suite, idxs in suite_groups.items():
        mid_x = (centres[idxs[0]] + centres[idxs[-1]]) / 2
        ax.text(
            mid_x, y_top * 1.08,
            suite_display.get(suite, suite),
            ha="center", va="center", fontsize=10, fontweight="bold", color="#444",
        )

    ax.set_ylabel("Duration (seconds)", fontsize=10)
    ax.set_title("Dev-workflow benchmark — latest run per machine", fontsize=12, pad=14)
    ax.yaxis.grid(True, linestyle=":", alpha=0.6, zorder=0)
    ax.set_axisbelow(True)

    # Deduplicated legend
    legend_handles = [
        mpatches.Patch(color=host_colours[h], label=h) for h in hosts
    ]
    ax.legend(handles=legend_handles, title="Machine", loc="upper right", fontsize=9)

    fig.tight_layout()
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"Saved: {out_path}")

    # Show if a display is available; silently skip in headless / Agg environments.
    if matplotlib.get_backend().lower() not in ("agg", "pdf", "svg", "ps"):
        plt.show()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    args = sys.argv[1:]

    if args:
        csv_paths = args
    else:
        # Default: all *.csv files in the parent directory (repo root)
        parent = pathlib.Path(__file__).resolve().parent.parent
        csv_paths = sorted(glob.glob(str(parent / "*.csv")))
        if not csv_paths:
            raise SystemExit(
                "No CSV files found in the parent directory. "
                "Pass explicit paths: pixi run plot -- file1.csv file2.csv"
            )
        print(f"Auto-discovered {len(csv_paths)} CSV file(s) from {parent}")

    print(f"Loading {len(csv_paths)} file(s)…")
    for p in csv_paths:
        print(f"  {p}")

    df = load_csvs(csv_paths)
    df = latest_per_host_phase(df)

    print(f"\nMachines : {sorted(df['hostname'].unique())}")
    print(f"Phases   : {sorted(df['phase'].unique())}")
    print(f"Rows     : {len(df)}\n")

    out_path = pathlib.Path(__file__).resolve().parent / "results_plot.png"
    plot(df, out_path)


if __name__ == "__main__":
    main()
