#!/usr/bin/env python3
"""
Plot FlightCap CSV exports with the same semantics as ConnectedView:
  - Motion: interactions vs time (scatter points only)
  - Distance: distance_mm vs time (scatter points only)
  - Red vertical lines at user_flag timestamps

Usage:
  python plot_flightcap.py FlightCap_F3-EF-5D-FE-21-C9_2026-07-01T19-41-36Z.csv
  python plot_flightcap.py data.csv --window-minutes 10
  python plot_flightcap.py data.csv --save plots.png
"""

from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import matplotlib
import matplotlib.dates as mdates

import pandas as pd

# Matches FlightCap/Theme.swift accent colors
MOTION_COLOR = "#59EBFF"    # rgb(0.35, 0.92, 1.00)
DISTANCE_COLOR = "#FF6BA6"  # rgb(1.00, 0.42, 0.65)
FLAG_COLOR = "red"


def local_timezone() -> ZoneInfo:
    """Best-effort system IANA timezone (macOS/Linux)."""
    import os
    import subprocess

    if tz_name := os.environ.get("TZ"):
        return ZoneInfo(tz_name)

    for path in ("/etc/localtime", "/var/db/timezone/zoneinfo"):
        try:
            target = os.readlink(path)
            if "zoneinfo/" in target:
                return ZoneInfo(target.split("zoneinfo/")[-1])
            if "/" in target:
                return ZoneInfo(target.rsplit("/", 1)[-1])
        except OSError:
            continue

    try:
        out = subprocess.check_output(["systemsetup", "-gettimezone"], text=True)
        # e.g. "Time Zone: America/Chicago"
        if ":" in out:
            return ZoneInfo(out.split(":", 1)[1].strip())
    except Exception:
        pass

    raise SystemExit(
        "Could not detect local timezone. Pass --tz America/Chicago explicitly."
    )


def load_csv(path: Path, tz: ZoneInfo) -> pd.DataFrame:
    df = pd.read_csv(path)
    # Matplotlib date formatters ignore tz on axis values; store naive local times.
    df["datetime"] = (
        pd.to_datetime(df["datetime"], utc=True)
        .dt.tz_convert(tz)
        .dt.tz_localize(None)
    )
    df["interactions"] = pd.to_numeric(df["interactions"], errors="coerce")
    df["distance_mm"] = pd.to_numeric(df["distance_mm"], errors="coerce")
    df["user_flag"] = df["user_flag"].astype(str).str.lower() == "true"
    return df.sort_values("datetime").reset_index(drop=True)


def y_limits(values: pd.Series) -> tuple[float, float]:
    """Mirror ConnectedView y-domain padding (includes zero when sensible)."""
    finite = values.dropna()
    if finite.empty:
        return 0.0, 1.0
    lo, hi = float(finite.min()), float(finite.max())
    if lo == hi:
        pad = max(1.0, abs(lo) * 0.1)
        return lo - pad, hi + pad
    span = hi - lo
    pad = span * 0.15
    lower = min(0.0, lo - pad)
    return lower, hi + pad


def x_limits(df: pd.DataFrame, window_minutes: float | None) -> tuple[pd.Timestamp, pd.Timestamp]:
    end = df["datetime"].max()
    if window_minutes is not None:
        start = end - pd.Timedelta(minutes=window_minutes)
    else:
        start = df["datetime"].min()
    return start, end


def plot_axis(
    ax,
    df: pd.DataFrame,
    *,
    title: str,
    y_col: str,
    y_label: str,
    color: str,
    x_start: pd.Timestamp,
    x_end: pd.Timestamp,
) -> None:
    flags = df.loc[df["user_flag"], "datetime"]
    for t in flags:
        if x_start <= t <= x_end:
            ax.axvline(t, color=FLAG_COLOR, linewidth=2, zorder=1)

    points = df.dropna(subset=[y_col])
    points = points[(points["datetime"] >= x_start) & (points["datetime"] <= x_end)]

    ax.scatter(
        points["datetime"],
        points[y_col],
        c=color,
        s=36,
        zorder=2,
        edgecolors="none",
    )

    ax.set_title(title)
    ax.set_ylabel(y_label)
    ax.set_xlim(x_start, x_end)
    ax.set_ylim(*y_limits(points[y_col]))
    ax.xaxis.set_major_locator(mdates.AutoDateLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    ax.grid(True, alpha=0.3)


def main() -> None:
    parser = argparse.ArgumentParser(description="Plot FlightCap exported telemetry CSV.")
    parser.add_argument("csv", type=Path, help="Path to exported CSV file")
    parser.add_argument(
        "--window-minutes",
        type=float,
        default=None,
        help="X-axis window length in minutes (default: full recording span)",
    )
    parser.add_argument(
        "--tz",
        default=None,
        help="IANA timezone for x-axis (default: system local, e.g. America/Chicago)",
    )
    parser.add_argument(
        "--save",
        type=Path,
        default=None,
        help="Save figure to this path instead of only showing interactively",
    )
    args = parser.parse_args()

    if args.save:
        matplotlib.use("Agg")

    import matplotlib.pyplot as plt

    tz = ZoneInfo(args.tz) if args.tz else local_timezone()
    df = load_csv(args.csv, tz)
    if df.empty:
        raise SystemExit("CSV has no rows.")

    x_start, x_end = x_limits(df, args.window_minutes)

    fig, (ax_motion, ax_dist) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)
    fig.suptitle(args.csv.name, fontsize=11)

    plot_axis(
        ax_motion,
        df,
        title="Motion",
        y_col="interactions",
        y_label="interactions",
        color=MOTION_COLOR,
        x_start=x_start,
        x_end=x_end,
    )
    plot_axis(
        ax_dist,
        df,
        title="Distance",
        y_col="distance_mm",
        y_label="mm",
        color=DISTANCE_COLOR,
        x_start=x_start,
        x_end=x_end,
    )
    ax_dist.set_xlabel(f"Local time ({tz})")

    fig.tight_layout()

    if args.save:
        fig.savefig(args.save, dpi=150, bbox_inches="tight")
        print(f"Saved {args.save}")
    else:
        plt.show()


if __name__ == "__main__":
    main()
