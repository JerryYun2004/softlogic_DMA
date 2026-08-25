#!/usr/bin/env python3
"""Compare the shared-FSM schedule against the supplied reference loop nests.

This is a simulator-independent sanity check.  The SystemVerilog regression is
the authoritative RTL test; this script is useful on hosts where iverilog is
not yet installed.
"""

from __future__ import annotations

from dataclasses import dataclass


MASK32 = (1 << 32) - 1
IMAGE_BASE = 0x1000_0000
WEIGHT_BASE = 0x2000_0000


@dataclass(frozen=True)
class Command:
    source: int
    stride: int
    destination: int
    bank_mask: int
    is_weight: bool
    zero_fill: bool
    last: bool


def u32(value: int) -> int:
    return value & MASK32


def rtl_activation_schedule(
    conv_1x1: bool, tile_y: int, tile_x: int, cin_block: int
) -> list[Command]:
    if conv_1x1:
        offset = tile_y * 8192 + tile_x * 256 + cin_block * 8
        side = 16
        row_step = 272
    else:
        offset_lut = {
            (0, 0, 0): -528,
            (0, 0, 1): -520,
            (0, 1, 0): -272,
            (0, 1, 1): -264,
            (1, 0, 0): 7664,
            (1, 0, 1): 7672,
            (1, 1, 0): 7920,
            (1, 1, 1): 7928,
        }
        offset = offset_lut[tile_y, tile_x, cin_block]
        side = 18
        row_step = 240

    source = u32(IMAGE_BASE + offset)
    commands: list[Command] = []
    row_end_registered = False
    local_y = 0
    local_x = 0
    count = 0
    final_count = side * side - 1

    while True:
        zero_fill = (
            not conv_1x1
            and (
                (tile_y == 0 and local_y == 0)
                or (tile_y == 1 and local_y == 17)
                or (tile_x == 0 and local_x == 0)
                or (tile_x == 1 and local_x == 17)
            )
        )
        commands.append(
            Command(source, 1, count, 0xFF, False, zero_fill, count == final_count)
        )

        if count == final_count:
            return commands

        count += 1
        source = u32(source + (row_step if row_end_registered else 16))
        if row_end_registered:
            local_y += 1
            local_x = 0
            row_end_registered = False
        else:
            row_end_registered = local_x == (14 if conv_1x1 else 16)
            local_x += 1


def reference_activation_schedule(
    conv_1x1: bool, tile_y: int, tile_x: int, cin_block: int
) -> list[Command]:
    side = 16 if conv_1x1 else 18
    commands: list[Command] = []
    for local_y in range(side):
        for local_x in range(side):
            if conv_1x1:
                global_y = tile_y * 16 + local_y
                global_x = tile_x * 16 + local_x
            else:
                global_y = tile_y * 16 + local_y - 1
                global_x = tile_x * 16 + local_x - 1

            destination = local_y * side + local_x
            source = u32(
                IMAGE_BASE
                + ((global_y * 32 + global_x) * 16)
                + cin_block * 8
            )
            zero_fill = not conv_1x1 and (
                global_y < 0 or global_y >= 32 or global_x < 0 or global_x >= 32
            )
            commands.append(
                Command(
                    source,
                    1,
                    destination,
                    0xFF,
                    False,
                    zero_fill,
                    destination == side * side - 1,
                )
            )
    return commands


def rtl_weight_schedule(
    conv_1x1: bool, kernel_y: int, kernel_x: int, cin_block: int, cout_block: int
) -> list[Command]:
    tap = 0 if conv_1x1 else kernel_y * 3 + kernel_x
    source = u32(
        WEIGHT_BASE + tap * 256 + cin_block * 128 + cout_block * 8 + 7
    )
    return [
        Command(u32(source - shift), 16, shift, 0xFF, True, False, shift == 7)
        for shift in range(8)
    ]


def reference_weight_schedule(
    conv_1x1: bool, kernel_y: int, kernel_x: int, cin_block: int, cout_block: int
) -> list[Command]:
    commands: list[Command] = []
    tap = 0 if conv_1x1 else kernel_y * 3 + kernel_x
    for shift in range(8):
        output_column = 7 - shift
        source = u32(
            WEIGHT_BASE
            + tap * 16 * 16
            + cin_block * 8 * 16
            + cout_block * 8
            + output_column
        )
        commands.append(
            Command(source, 16, shift, 0xFF, True, False, shift == 7)
        )
    return commands


def main() -> None:
    activation_cases = 0
    weight_cases = 0
    commands_checked = 0
    zero_fills = 0

    for conv_1x1 in (False, True):
        for tile_y in range(2):
            for tile_x in range(2):
                for cin_block in range(2):
                    actual = rtl_activation_schedule(
                        conv_1x1, tile_y, tile_x, cin_block
                    )
                    expected = reference_activation_schedule(
                        conv_1x1, tile_y, tile_x, cin_block
                    )
                    assert actual == expected, (
                        "activation schedule mismatch",
                        conv_1x1,
                        tile_y,
                        tile_x,
                        cin_block,
                    )
                    activation_cases += 1
                    commands_checked += len(actual)
                    zero_fills += sum(command.zero_fill for command in actual)

    for conv_1x1 in (False, True):
        ky_values = range(1) if conv_1x1 else range(3)
        kx_values = range(1) if conv_1x1 else range(3)
        for kernel_y in ky_values:
            for kernel_x in kx_values:
                for cin_block in range(2):
                    for cout_block in range(2):
                        actual = rtl_weight_schedule(
                            conv_1x1,
                            kernel_y,
                            kernel_x,
                            cin_block,
                            cout_block,
                        )
                        expected = reference_weight_schedule(
                            conv_1x1,
                            kernel_y,
                            kernel_x,
                            cin_block,
                            cout_block,
                        )
                        assert actual == expected, (
                            "weight schedule mismatch",
                            conv_1x1,
                            kernel_y,
                            kernel_x,
                            cin_block,
                            cout_block,
                        )
                        weight_cases += 1
                        commands_checked += len(actual)

    assert activation_cases == 16
    assert weight_cases == 40
    assert zero_fills == 280
    print(
        "PASS: reference schedules match shared-FSM model "
        f"({activation_cases} activation cases, {weight_cases} weight cases, "
        f"{commands_checked} commands, {zero_fills} zero fills)"
    )


if __name__ == "__main__":
    main()
