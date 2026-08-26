#!/usr/bin/env python3
"""Check packed row descriptors, map groups, and the AXI4 burst plan.

This simulator-independent model mirrors the packed-source RTL. The
SystemVerilog regressions remain authoritative, but this check runs on hosts
without an HDL simulator.
"""

from __future__ import annotations

from dataclasses import dataclass


MASK32 = (1 << 32) - 1
IMAGE_BASE = 0x1000_0000
WEIGHT_BASE = 0x2000_0000


@dataclass(frozen=True)
class RowDescriptor:
    source: int
    destination: int
    groups: int
    pad_before: bool
    pad_after: bool
    is_weight: bool
    zero_fill: bool
    last: bool


@dataclass(frozen=True)
class MapGroup:
    source: int
    destination: int
    is_weight: bool
    zero_fill: bool
    last: bool


@dataclass(frozen=True)
class ReadBurst:
    """One AXI INCR read burst; beats are 32 bits each."""

    address: int
    beats: int


def u32(value: int) -> int:
    return value & MASK32


def activation_descriptors(
    base: int, conv_1x1: bool, tile_y: int, tile_x: int
) -> list[RowDescriptor]:
    """Mirror the AGU's packed activation-row descriptors."""
    rows = 16 if conv_1x1 else 18
    source = base
    descriptors: list[RowDescriptor] = []

    for row in range(rows):
        pad_row = not conv_1x1 and (
            (tile_y == 0 and row == 0) or (tile_y == 1 and row == 17)
        )
        descriptors.append(
            RowDescriptor(
                source=u32(source),
                destination=row * (16 if conv_1x1 else 18),
                groups=16 if conv_1x1 else (18 if pad_row else 17),
                pad_before=not conv_1x1 and not pad_row and tile_x == 0,
                pad_after=not conv_1x1 and not pad_row and tile_x == 1,
                is_weight=False,
                zero_fill=pad_row,
                last=row == rows - 1,
            )
        )
        if not pad_row:
            source += 128 if conv_1x1 else 136

    return descriptors


def weight_descriptor(base: int) -> RowDescriptor:
    """One packed 8x8 slice is one descriptor and one 16-beat burst."""
    return RowDescriptor(base, 0, 8, False, False, True, False, True)


def expand_groups(descriptor: RowDescriptor) -> list[MapGroup]:
    groups: list[MapGroup] = []

    if descriptor.zero_fill:
        for index in range(descriptor.groups):
            groups.append(
                MapGroup(
                    u32(descriptor.source + index * 8),
                    descriptor.destination + index,
                    False,
                    True,
                    descriptor.last and index == descriptor.groups - 1,
                )
            )
        return groups

    if descriptor.pad_before:
        groups.append(
            MapGroup(
                descriptor.source,
                descriptor.destination,
                False,
                True,
                False,
            )
        )

    for index in range(descriptor.groups):
        groups.append(
            MapGroup(
                u32(descriptor.source + index * 8),
                descriptor.destination + int(descriptor.pad_before) + index,
                descriptor.is_weight,
                False,
                descriptor.last
                and not descriptor.pad_after
                and index == descriptor.groups - 1,
            )
        )

    if descriptor.pad_after:
        groups.append(
            MapGroup(
                u32(descriptor.source + descriptor.groups * 8),
                descriptor.destination + descriptor.groups,
                False,
                True,
                descriptor.last,
            )
        )

    return groups


def axi_read_plan(descriptor: RowDescriptor) -> list[ReadBurst]:
    """Create long bursts and split only where AXI's 4 KiB rule requires."""
    if descriptor.zero_fill:
        return []

    address = descriptor.source
    beats_left = descriptor.groups * 2
    bursts: list[ReadBurst] = []
    while beats_left:
        beats_to_4k = (4096 - (address & 0xFFF)) // 4
        beats = min(beats_left, beats_to_4k)
        assert 1 <= beats <= 256
        bursts.append(ReadBurst(u32(address), beats))
        address = u32(address + beats * 4)
        beats_left -= beats
    return bursts


def patterned_byte(address: int) -> int:
    """Same deterministic byte function used by the RTL unit test."""
    return (
        (address >> 0)
        ^ (address >> 8)
        ^ (address >> 16)
        ^ (address >> 24)
    ) & 0xFF


def execute_fetch(descriptor: RowDescriptor) -> list[tuple[int, ...]]:
    fetched: list[tuple[int, ...]] = []
    for group in expand_groups(descriptor):
        if group.zero_fill:
            fetched.append((0,) * 8)
        else:
            fetched.append(
                tuple(patterned_byte(group.source + lane) for lane in range(8))
            )
    return fetched


def validate_bursts(descriptor: RowDescriptor, bursts: list[ReadBurst]) -> None:
    if descriptor.zero_fill:
        assert bursts == []
        return

    assert sum(burst.beats for burst in bursts) == descriptor.groups * 2
    assert bursts[0].address == descriptor.source
    for burst in bursts:
        assert burst.address % 4 == 0
        assert 1 <= burst.beats <= 256
        assert (burst.address & 0xFFF) + burst.beats * 4 <= 4096
    for before, after in zip(bursts, bursts[1:]):
        assert u32(before.address + before.beats * 4) == after.address


def main() -> None:
    activation_cases = 0
    weight_cases = 0
    descriptors_checked = 0
    groups_checked = 0
    zero_fills = 0
    bursts_checked = 0
    beats_checked = 0

    for conv_1x1 in (False, True):
        for tile_y in range(2):
            for tile_x in range(2):
                for cin_block in range(2):
                    # The block/tile selection changes which packed pointer
                    # software supplies, not an offset added inside the DMA.
                    case_index = (((int(conv_1x1) * 2 + tile_y) * 2 + tile_x)
                                  * 2 + cin_block)
                    base = IMAGE_BASE + case_index * 0x1000
                    descriptors = activation_descriptors(
                        base, conv_1x1, tile_y, tile_x
                    )
                    groups = [
                        group
                        for descriptor in descriptors
                        for group in expand_groups(descriptor)
                    ]

                    expected_groups = 256 if conv_1x1 else 324
                    assert len(groups) == expected_groups
                    assert [group.destination for group in groups] == list(
                        range(expected_groups)
                    )
                    assert sum(group.last for group in groups) == 1
                    assert sum(group.zero_fill for group in groups) == (
                        0 if conv_1x1 else 35
                    )

                    case_bursts = []
                    for descriptor in descriptors:
                        burst_plan = axi_read_plan(descriptor)
                        validate_bursts(descriptor, burst_plan)
                        case_bursts.extend(burst_plan)
                        assert len(execute_fetch(descriptor)) == len(
                            expand_groups(descriptor)
                        )

                    assert len(case_bursts) == (16 if conv_1x1 else 17)
                    assert all(
                        burst.beats == (32 if conv_1x1 else 34)
                        for burst in case_bursts
                    )

                    activation_cases += 1
                    descriptors_checked += len(descriptors)
                    groups_checked += len(groups)
                    zero_fills += sum(group.zero_fill for group in groups)
                    bursts_checked += len(case_bursts)
                    beats_checked += sum(burst.beats for burst in case_bursts)

    for conv_1x1 in (False, True):
        ky_values = range(1) if conv_1x1 else range(3)
        kx_values = range(1) if conv_1x1 else range(3)
        for kernel_y in ky_values:
            for kernel_x in kx_values:
                for cin_block in range(2):
                    for cout_block in range(2):
                        slice_index = weight_cases
                        base = WEIGHT_BASE + slice_index * 64
                        descriptor = weight_descriptor(base)
                        groups = expand_groups(descriptor)
                        bursts = axi_read_plan(descriptor)
                        validate_bursts(descriptor, bursts)
                        assert len(groups) == 8
                        assert [group.destination for group in groups] == list(
                            range(8)
                        )
                        assert sum(group.last for group in groups) == 1
                        assert len(bursts) == 1
                        assert bursts[0].beats == 16
                        assert len(execute_fetch(descriptor)) == 8

                        weight_cases += 1
                        descriptors_checked += 1
                        groups_checked += 8
                        bursts_checked += 1
                        beats_checked += 16

    # Explicitly exercise the optional activation-row 4 KiB split path.
    crossing = RowDescriptor(
        source=0x3000_0FC0,
        destination=0,
        groups=16,
        pad_before=False,
        pad_after=False,
        is_weight=False,
        zero_fill=False,
        last=True,
    )
    crossing_plan = axi_read_plan(crossing)
    assert crossing_plan == [
        ReadBurst(0x3000_0FC0, 16),
        ReadBurst(0x3000_1000, 16),
    ]
    validate_bursts(crossing, crossing_plan)

    assert activation_cases == 16
    assert weight_cases == 40
    assert descriptors_checked == 312
    assert groups_checked == 4960
    assert zero_fills == 280
    assert bursts_checked == 304
    assert beats_checked == 9360
    print(
        "PASS: packed schedules and long-burst AXI plan match the reference "
        f"model ({activation_cases} activation cases, {weight_cases} weight "
        f"cases, {descriptors_checked} row/slice descriptors, "
        f"{groups_checked} map groups, {zero_fills} zero fills, "
        f"{bursts_checked} bursts, {beats_checked} 32-bit beats)"
    )


if __name__ == "__main__":
    main()
