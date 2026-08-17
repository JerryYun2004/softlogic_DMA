#!/usr/bin/env python3
"""Exhaustively verify weight and activation mapping command streams."""

TILE_BASE = 0x123
IMAGE_WIDTH = 37
WEIGHT_BASE = 0x800
OUT_W = 14
OUT_COUNT = 196
NUM_TAPS = 9
NUM_COLUMNS = 8


def valid_qs(tile_row, tile_col, kernel_row):
    qs = []
    for kernel_col in range(3):
        output_row = tile_row - kernel_row
        output_col = tile_col - kernel_col
        q = 3 * kernel_row + kernel_col
        if 0 <= output_row < 14 and 0 <= output_col < 14 and q < 8:
            qs.append(q)
    return qs


def weight_command_stream():
    commands = []
    for q in range(NUM_TAPS):
        for column in range(NUM_COLUMNS):
            commands.append(
                {
                    "source": WEIGHT_BASE + NUM_COLUMNS * q + column,
                    "buffer": q,
                    "mask": 1 << column,
                    "is_weight": True,
                    "pass": int(q == 8),
                    "source_first": True,
                    "source_last": True,
                    "pass_last": column == 7 and q in (7, 8),
                }
            )
    assert len(commands) == 72
    return commands


def activation_command_stream():
    commands = []

    for tile_row in range(16):
        for tile_col in range(16):
            groups = []
            for kernel_row in range(3):
                qs = valid_qs(tile_row, tile_col, kernel_row)
                if qs:
                    groups.append(
                        (
                            14 * tile_row + tile_col - 11 * kernel_row,
                            sum(1 << q for q in qs),
                        )
                    )

            source = TILE_BASE + tile_row * IMAGE_WIDTH + tile_col
            for group_index, (buffer_addr, row_mask) in enumerate(groups):
                commands.append(
                    {
                        "source": source,
                        "buffer": buffer_addr,
                        "mask": row_mask,
                        "is_weight": False,
                        "pass": 0,
                        "source_first": group_index == 0,
                        "source_last": group_index == len(groups) - 1,
                        "pass_last": (tile_row, tile_col) == (15, 14)
                        and group_index == len(groups) - 1,
                    }
                )

    assert len(commands) == 658

    for output_row in range(14):
        for output_col in range(14):
            commands.append(
                {
                    "source": TILE_BASE
                    + (output_row + 2) * IMAGE_WIDTH
                    + output_col
                    + 2,
                    "buffer": 14 * output_row + output_col,
                    "mask": 0x01,
                    "is_weight": False,
                    "pass": 1,
                    "source_first": True,
                    "source_last": True,
                    "pass_last": (output_row, output_col) == (13, 13),
                }
            )

    assert len(commands) == 854
    return commands


def command_stream():
    return weight_command_stream() + activation_command_stream()


def verify_weights(commands):
    weights = [command for command in commands if command["is_weight"]]
    assert len(weights) == 72
    assert sum(command["pass_last"] for command in weights) == 2

    for index, command in enumerate(weights):
        q, column = divmod(index, NUM_COLUMNS)
        assert command["source"] == WEIGHT_BASE + index
        assert command["buffer"] == q
        assert command["mask"] == 1 << column
        assert command["pass"] == int(q == 8)
        assert command["source_first"]
        assert command["source_last"]


def verify_destinations(commands):
    pass0_destinations = {}
    for command in commands:
        assert command["mask"] != 0
        if command["is_weight"] or command["pass"] != 0:
            continue
        for physical_row in range(8):
            if (command["mask"] >> physical_row) & 1:
                key = physical_row, command["buffer"]
                assert key not in pass0_destinations
                pass0_destinations[key] = command["source"]

    for physical_row in range(8):
        kernel_row, kernel_col = divmod(physical_row, 3)
        for buffer_addr in range(203):
            output_index = buffer_addr - physical_row
            expected = None
            if 0 <= output_index < OUT_COUNT:
                output_row, output_col = divmod(output_index, OUT_W)
                expected = (
                    TILE_BASE
                    + (output_row + kernel_row) * IMAGE_WIDTH
                    + output_col
                    + kernel_col
                )
            assert pass0_destinations.get((physical_row, buffer_addr)) == expected

    pass1 = [
        command
        for command in commands
        if not command["is_weight"] and command["pass"] == 1
    ]
    assert len(pass1) == 196
    for output_index, command in enumerate(pass1):
        output_row, output_col = divmod(output_index, OUT_W)
        assert command["buffer"] == output_index
        assert command["mask"] == 0x01
        assert command["source"] == (
            TILE_BASE
            + (output_row + 2) * IMAGE_WIDTH
            + output_col
            + 2
        )


def main():
    commands = command_stream()
    weights = [command for command in commands if command["is_weight"]]
    activations = [command for command in commands if not command["is_weight"]]

    assert len(commands) == 926
    assert len(weights) == 72
    assert len(activations) == 854
    assert sum(c["mask"].bit_count() for c in weights) == 72
    assert sum(c["mask"].bit_count() for c in activations) == 1764
    assert sum(c["pass_last"] for c in commands) == 4
    assert sum(c["source_first"] for c in weights) == 72
    assert sum(c["source_first"] for c in activations) == 451
    verify_weights(commands)
    verify_destinations(commands)

    print("PASS: protocol-neutral weight and activation streams verified")
    print("weights: 72 commands representing 72 column-buffer writes")
    print("activation pass0: 658 commands representing 1568 row writes")
    print("activation pass1: 196 commands representing 196 row writes")
    print("activation total: 854 commands representing 1764 row writes")
    print("activation SRAM reads: 255 in pass0 + 196 in pass1 = 451")
    print("combined total: 926 commands representing 1836 buffer writes")


if __name__ == "__main__":
    main()
