#!/usr/bin/env python3
"""Exhaustive mathematical check for the grouped row-buffer DMA schedule."""

OUT_W = 14
OUT_COUNT = 196


def horizontal_taps(tile_col):
    return [kx for kx in range(3) if 0 <= tile_col - kx < OUT_W]


def pass0_groups():
    """Yield (tile_row, tile_col, buffer_addr, row_mask)."""
    for tile_row in range(16):
        # X[15,15] is used only by q=8 in pass 1.
        last_col = 14 if tile_row == 15 else 15
        for tile_col in range(last_col + 1):
            valid_kx = horizontal_taps(tile_col)
            linear = 14 * tile_row + tile_col
            for ky in range(3):
                if not (0 <= tile_row - ky < OUT_W):
                    continue
                qs = [3 * ky + kx for kx in valid_kx if 3 * ky + kx < 8]
                if qs:
                    mask = sum(1 << q for q in qs)
                    yield tile_row, tile_col, linear - 11 * ky, mask


def pass1_groups():
    """Yield (tile_row, tile_col, buffer_addr, row_mask)."""
    for output_row in range(14):
        for output_col in range(14):
            yield (
                output_row + 2,
                output_col + 2,
                14 * output_row + output_col,
                0x01,
            )


def check_pass0_equivalence():
    destinations = {}
    groups = list(pass0_groups())

    for tile_row, tile_col, buffer_addr, mask in groups:
        for physical_row in range(8):
            if (mask >> physical_row) & 1:
                key = physical_row, buffer_addr
                assert key not in destinations, f"duplicate destination {key}"
                destinations[key] = tile_row, tile_col

    for physical_row in range(8):
        ky, kx = divmod(physical_row, 3)
        for buffer_addr in range(203):
            output_index = buffer_addr - physical_row
            expected = None
            if 0 <= output_index < OUT_COUNT:
                output_row, output_col = divmod(output_index, OUT_W)
                expected = output_row + ky, output_col + kx
            assert destinations.get((physical_row, buffer_addr)) == expected

    assert len(groups) == 658
    assert len({(a, b) for a, b, _, _ in groups}) == 255
    assert sum(mask.bit_count() for _, _, _, mask in groups) == 1568


def check_pass1_equivalence():
    groups = list(pass1_groups())
    assert len(groups) == 196
    for tile_row, tile_col, buffer_addr, mask in groups:
        output_row, output_col = divmod(buffer_addr, OUT_W)
        assert (tile_row, tile_col) == (output_row + 2, output_col + 2)
        assert mask == 0x01


def cached_word_reads(tile_base, image_width):
    pass0_sources = [
        tile_base + tile_row * image_width + tile_col
        for tile_row in range(16)
        for tile_col in range(15 if tile_row == 15 else 16)
    ]
    pass1_sources = [
        tile_base + tile_row * image_width + tile_col
        for tile_row in range(2, 16)
        for tile_col in range(2, 16)
    ]

    def count_one_word_cache(addresses):
        cached_word = None
        reads = 0
        for address in addresses:
            word = address >> 2
            if word != cached_word:
                cached_word = word
                reads += 1
        return reads

    # RTL invalidates the cache between passes.
    return count_one_word_cache(pass0_sources), count_one_word_cache(pass1_sources)


def main():
    check_pass0_equivalence()
    check_pass1_equivalence()

    # Check address traversal across several alignments and legal image widths.
    for base_alignment in range(4):
        for image_width in range(16, 80):
            p0_reads, p1_reads = cached_word_reads(base_alignment, image_width)
            assert 64 <= p0_reads <= 80
            assert 56 <= p1_reads <= 70

    p0_reads, p1_reads = cached_word_reads(0x100, 64)
    assert (p0_reads, p1_reads) == (64, 56)

    print("PASS: grouped schedule equals destination-by-destination mapping")
    print("pass0: 255 source pixels, 658 mask commands, 1568 selected rows")
    print("pass1: 196 source pixels, 196 mask commands, 196 selected rows")
    print("test configuration: 64 + 56 = 120 aligned AXI word reads")


if __name__ == "__main__":
    main()
