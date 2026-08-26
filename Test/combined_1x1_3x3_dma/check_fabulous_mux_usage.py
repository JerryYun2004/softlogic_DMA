#!/usr/bin/env python3
"""Reject manually forced FABulous cascade muxes in the PnR-legal baseline."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


MUX_TYPES = ("FABULOUS_MUX2", "FABULOUS_MUX4", "FABULOUS_MUX8")


def normalized(name: str) -> str:
    """Remove the optional RTLIL escape prefix from a cell/module name."""
    return name[1:] if name.startswith("\\") else name


def find_module(modules: dict[str, object], requested: str) -> str | None:
    if requested in modules:
        return requested
    for name in modules:
        if normalized(name) == normalized(requested):
            return name
    return None


def count_hierarchy(
    modules: dict[str, dict[str, object]], top: str
) -> Counter[str]:
    counts: Counter[str] = Counter()

    def visit(module_name: str, active_path: tuple[str, ...]) -> None:
        if module_name in active_path:
            cycle = " -> ".join((*active_path, module_name))
            raise ValueError(f"recursive module hierarchy: {cycle}")

        module = modules[module_name]
        cells = module.get("cells", {})
        if not isinstance(cells, dict):
            raise ValueError(f"module {module_name!r} has a malformed cell table")

        for cell in cells.values():
            if not isinstance(cell, dict) or "type" not in cell:
                raise ValueError(f"module {module_name!r} has a malformed cell")
            raw_type = str(cell["type"])
            cell_type = normalized(raw_type)
            counts[cell_type] += 1

            child = find_module(modules, raw_type)
            if child is not None:
                visit(child, (*active_path, module_name))

    visit(top, ())
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json", type=Path, help="Yosys JSON passed to nextpnr")
    parser.add_argument("--top", default="top_wrapper", help="top module name")
    parser.add_argument("--max-mux2", type=int, default=0)
    parser.add_argument("--max-mux4", type=int, default=0)
    parser.add_argument("--max-mux8", type=int, default=0)
    args = parser.parse_args()

    try:
        design = json.loads(args.json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        parser.error(f"cannot read {args.json}: {error}")

    modules = design.get("modules")
    if not isinstance(modules, dict):
        parser.error(f"{args.json} does not contain a Yosys module table")

    top = find_module(modules, args.top)
    if top is None:
        available = ", ".join(sorted(normalized(name) for name in modules))
        parser.error(f"top {args.top!r} not found; available modules: {available}")

    try:
        counts = count_hierarchy(modules, top)
    except ValueError as error:
        parser.error(str(error))

    limits = {
        "FABULOUS_MUX2": args.max_mux2,
        "FABULOUS_MUX4": args.max_mux4,
        "FABULOUS_MUX8": args.max_mux8,
    }
    excess = [
        f"{cell_type}={counts[cell_type]} (need <= {maximum})"
        for cell_type, maximum in limits.items()
        if counts[cell_type] > maximum
    ]

    summary = ", ".join(f"{name}={counts[name]}" for name in MUX_TYPES)
    lc_count = counts["FABULOUS_LC"]
    if excess:
        print(f"FAIL: {summary}; " + "; ".join(excess))
        print(
            "The current RTL must not instantiate FABULOUS_MUX2/4/8 "
            "directly. These BELs are LUT cascades; nextpnr requires every "
            "data input to be driven by a clustered FABULOUS_LC/COMB O port."
        )
        return 1

    print(
        f"PASS: synthesized hierarchy {normalized(top)} has no manually "
        f"forced cascade muxes ({summary}); FABULOUS_LC={lc_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
