#!/usr/bin/env python3
"""Bump the top-level `version:` field of a Helm Chart.yaml.

Editing the version by reserializing the whole YAML strips comments and reorders
keys, and a naive search can hit `appVersion:` or a dependency's indented
`version:`. This script edits only the top-level `version:` line, preserves the
rest of the file byte-for-byte, keeps any leading `v` prefix and quoting the
chart already uses, and refuses to write a version that is not strictly greater
than the current one. Stdlib only (Python 3.8+), so it runs anywhere.

Bump modes:
  patch   x.y.Z  -> x.y.(Z+1)   (default; bug fixes)
  minor   x.Y.z  -> x.(Y+1).0
  major   X.y.z  -> (X+1).0.0
  calver  smart monthly release per the CMP scheme (see references/versioning.md)
  set     explicit target via --to vYY.M.P

calver resolves the rollout month (default: today) to (two-digit year, month):
  month >  current major.minor -> vYY.M.0   (new monthly release)
  month == current major.minor -> patch bump (another release the same month)
  month <  current major.minor -> error (would move the chart backwards)

Output: a human summary plus one `RESULT_JSON: {...}` line so a caller can build
a commit message without re-parsing.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from pathlib import Path

# Anchored at column 0 so an indented dependency `  version:` never matches and
# `appVersion:` (a different key) is excluded. Groups: key+spaces, optional
# opening quote, value token (no quote/space/hash), matching close quote, and the
# trailing remainder (comment/whitespace) which is preserved verbatim.
_VERSION_LINE = re.compile(
    r'^(?P<key>version:[ \t]+)(?P<q>["\']?)(?P<val>[^"\'#\s]+)(?P=q)(?P<rest>.*)$'
)
_NAME_LINE = re.compile(r'^name:[ \t]+(?P<q>["\']?)(?P<val>[^"\'#\s]+)(?P=q)')
# [v]MAJOR.MINOR.PATCH with optional pre-release/build metadata (dropped on bump).
_SEMVER = re.compile(r'^(?P<v>v?)(?P<maj>\d+)\.(?P<min>\d+)\.(?P<pat>\d+)(?P<extra>[-+].*)?$')


class BumpError(Exception):
    pass


def find_chart_file(path_arg: str) -> Path:
    p = Path(path_arg)
    if p.is_dir():
        candidate = p / "Chart.yaml"
        if not candidate.is_file():
            raise BumpError(f"No Chart.yaml found in directory: {p}")
        return candidate
    if p.is_file():
        return p
    raise BumpError(f"Chart path does not exist: {p}")


def parse_version(raw: str):
    m = _SEMVER.match(raw.strip())
    if not m:
        raise BumpError(
            f"Current version {raw!r} is not MAJOR.MINOR.PATCH; cannot bump safely."
        )
    if m.group("extra"):
        sys.stderr.write(
            f"warning: dropping pre-release/build metadata {m.group('extra')!r} "
            f"from {raw!r} (a release bump produces a clean version)\n"
        )
    return m.group("v"), int(m.group("maj")), int(m.group("min")), int(m.group("pat"))


def compute_new(mode, cur, month, to):
    _prefix, maj, mn, pat = cur
    if mode == "patch":
        return maj, mn, pat + 1
    if mode == "minor":
        return maj, mn + 1, 0
    if mode == "major":
        return maj + 1, 0, 0
    if mode == "set":
        if not to:
            raise BumpError("--to is required when --bump set is used")
        _p, tmaj, tmn, tpat = parse_version(to)
        return tmaj, tmn, tpat
    if mode == "calver":
        if month:
            try:
                y, m = month.split("-")
                ty, tm = int(y) % 100, int(m)
            except ValueError:
                raise BumpError(f"--month must be YYYY-MM, got {month!r}")
        else:
            today = _dt.date.today()
            ty, tm = today.year % 100, today.month
        if (ty, tm) > (maj, mn):
            return ty, tm, 0
        if (ty, tm) == (maj, mn):
            return maj, mn, pat + 1
        raise BumpError(
            f"calver target v{ty}.{tm}.0 is behind current v{maj}.{mn}.{pat}; "
            f"refusing to move the chart backwards. Use --bump patch for a same-line "
            f"fix, or --bump set --to <version> to override deliberately."
        )
    raise BumpError(f"unknown bump mode: {mode}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Bump a Helm chart's version field.")
    ap.add_argument("chart", help="Path to Chart.yaml or a directory containing it")
    ap.add_argument(
        "--bump",
        default="patch",
        choices=["patch", "minor", "major", "calver", "set"],
        help="Bump mode (default: patch)",
    )
    ap.add_argument("--to", help="Explicit target version for --bump set (e.g. v24.5.0)")
    ap.add_argument("--month", help="Rollout month YYYY-MM for --bump calver (default: today)")
    ap.add_argument(
        "--prefix",
        choices=["keep", "v", "none"],
        default="keep",
        help="'v' prefix handling: keep existing (default), force 'v', or strip",
    )
    ap.add_argument("--dry-run", action="store_true", help="Print the result without writing")
    args = ap.parse_args(argv)

    try:
        chart_file = find_chart_file(args.chart)
        lines = chart_file.read_text().splitlines(keepends=True)

        ver_idx = next((i for i, ln in enumerate(lines) if _VERSION_LINE.match(ln)), None)
        if ver_idx is None:
            raise BumpError(
                f"No top-level `version:` line found in {chart_file}. "
                f"(Indented dependency versions and `appVersion` are ignored on purpose.)"
            )

        m = _VERSION_LINE.match(lines[ver_idx])
        cur_raw = m.group("val")
        cur = parse_version(cur_raw)

        new_maj, new_min, new_pat = compute_new(args.bump, cur, args.month, args.to)
        out_prefix = cur[0] if args.prefix == "keep" else ("v" if args.prefix == "v" else "")
        new_version = f"{out_prefix}{new_maj}.{new_min}.{new_pat}"

        if (new_maj, new_min, new_pat) <= (cur[1], cur[2], cur[3]):
            raise BumpError(
                f"new version {new_version} is not greater than current "
                f"{cur_raw}; refusing to write a non-increasing version."
            )

        chart_name = next(
            (nm.group("val") for nm in (_NAME_LINE.match(ln) for ln in lines) if nm), None
        )

        original = lines[ver_idx]
        newline = original[len(original.rstrip("\r\n")):]  # reattach the exact line ending
        lines[ver_idx] = (
            f'{m.group("key")}{m.group("q")}{new_version}{m.group("q")}{m.group("rest")}' + newline
        )

        result = {
            "chart_file": str(chart_file),
            "chart_name": chart_name,
            "old_version": cur_raw,
            "new_version": new_version,
            "bump": args.bump,
            "changed": new_version != cur_raw,
            "dry_run": bool(args.dry_run),
        }
        if not args.dry_run:
            chart_file.write_text("".join(lines))

        print(f"{'Would bump' if args.dry_run else 'Bumped'} "
              f"{chart_name or chart_file.name}: {cur_raw} -> {new_version}")
        print("RESULT_JSON: " + json.dumps(result))
        return 0
    except BumpError as e:
        sys.stderr.write(f"error: {e}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
