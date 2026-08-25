# General GEMM DMA for the 8x8 systolic-array NPU

This package adds a separate, pointer-and-stride GEMM DMA. It follows the GEMM
schedule in `tb_npu_top_with_srams.sv` and uses the same AXI4-Lite/configuration
and protocol-neutral `map_*` split as the CNN DMA.

## Files

- `user_design/gemm_dma/gemm_tile_dma_agu.sv`: synthesizable GEMM command/address generator.
- `user_design/gemm_dma/gemm_dma_axi_wrapper.sv`: synthesizable AXI4-Lite wrapper.
- `Test/gemm_dma/tb_gemm_dma_unit.sv`: standalone DMA/AXI/backpressure regression.
- `Test/gemm_dma/tb_npu_gemm_dma_integrated.sv`: complete 1024x32 @ 32x32 NPU regression.
- `Test/gemm_dma/Makefile.gemm_dma`: unit and integrated simulation targets.

Extract/copy the package into the root of `FABulous_demo_AXI_IO-main`; the
paths above will then sit beside the existing `user_design` and `Test` trees.

## What one DMA launch does

The DMA is a tile loader, not a complete GEMM loop controller. Software retains
the inexpensive outer-loop arithmetic, while the existing NPU controller still
runs the 272-cycle linear compute pass and drains psums.

For row-major byte matrices `C = A @ B`:

```text
address(A[m][k]) = A_base + m*A_row_stride + k
address(B[k][n]) = B_base + k*B_row_stride + n
```

An A-panel launch emits one command per matrix row (1 to 256 commands). Command
`p` loads eight contiguous K elements into the eight activation SRAM banks at
destination address `p`.

A B-tile launch emits eight weight commands. It visits B columns 7 down to 0,
and each command reads eight B rows separated by `B_row_stride`. This exactly
matches the supplied `dma_load_weights_slice` task. A disabled shift cycle and
one-cycle `map_weight_swap` pulse follow the eighth accepted command.

The 1024x32 @ 32x32 reference workload therefore uses:

```text
A tile pointer = A_base + (m_tile*256)*32 + k_tile*8
B tile pointer = B_base + (k_tile*8)*32 + n_tile*8
A row stride   = 32 bytes
B row stride   = 32 bytes
```

The 32-bit stride output is intentional: the reference GEMM B matrix already
needs a stride of 32 bytes, which does not fit the CNN DMA's five-bit stride.

## Generality and edge conditions

- A and B can have arbitrary base addresses and row strides.
- An A panel can contain 1 to 256 rows, so an M remainder is handled directly.
- K and N are tiled in groups of eight because the physical array is 8x8.
- For K or N remainders, software or the source-memory adapter must present a
  zero-padded 8-element edge tile. This keeps the synthesizable AGU small.
- Each `map_*` command describes eight byte reads. The future memory adapter can
  satisfy a command with one 64-bit access or serialize it over a narrow SRAM
  port; no AGU change is required.

## AXI4-Lite register map

| Address | Access | Meaning |
|---|---|---|
| `0x00` | W | Write source tile pointer and start |
| `0x00` | R | Last accepted source tile pointer |
| `0x04` | R | `{error_sticky, busy, done_sticky}` in bits `[2:0]` |
| `0x08` | W/R | Bit 0: weight mode; bits `[8:1]`: A row count minus one |
| `0x0C` | W/R | Source row stride in bytes |

Write `0x08` and `0x0C` before writing `0x00`. A start with a zero row stride is
rejected with AXI `SLVERR` and sets `error_sticky`.

## Command contract

For an accepted activation command and lane `r`:

```text
source byte = map_source_addr + r              (map_source_stride = 1)
destination = activation_bank[r][map_buffer_addr]
```

For an accepted weight command and PE row `r`:

```text
source byte = map_source_addr + r*map_source_stride
destination = weight_shift_in[r]
```

`map_ready` must acknowledge the entire eight-byte group. In weight mode it
must assert only when the eight returned bytes are actually applied on a weight
shift clock, so the later swap pulse cannot overtake queued data.

## Make commands

From the repository root:

```bash
make -f Test/gemm_dma/Makefile.gemm_dma clean
make -f Test/gemm_dma/Makefile.gemm_dma unit
make -f Test/gemm_dma/Makefile.gemm_dma integrated
```

Run both regressions:

```bash
make -f Test/gemm_dma/Makefile.gemm_dma all
```

Or from the test directory:

```bash
cd Test/gemm_dma
make -f Makefile.gemm_dma unit
make -f Makefile.gemm_dma integrated
```

If the six existing NPU RTL files are elsewhere:

```bash
make -f Test/gemm_dma/Makefile.gemm_dma integrated \
  NPU_DIR=/absolute/path/to/user_design
```

The expected terminal endings are:

```text
PASS: GEMM DMA unit regression completed with no errors
PASS: DMA-integrated 1024x32 @ 32x32 GEMM matched all 32768 outputs
```

## Validation completed for this package

- The standalone AXI/DMA regression was compiled and simulated successfully.
- The two synthesizable RTL modules passed SystemVerilog parsing, hierarchy,
  process lowering, optimization, and `check -assert` with zero Yosys problems
  and no inferred latches.
- The integrated testbench compiled against an interface-equivalent
  `npu_sram_wrapper` stub. The uploaded references did not include the six NPU
  implementation files, so run the `integrated` target in the complete
  FABulous repository to execute the real end-to-end NPU regression.

The adapter inside the integrated testbench is simulation-only. It models a
source capable of returning all eight bytes in one cycle; production integration
still needs the memory-width-specific adapter discussed for the CNN DMA.
