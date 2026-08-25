# Combined 1x1 / 3x3 CNN DMA

This package replaces the separate 1x1 and 3x3 DMA bitstreams with one shared
DMA. The CPU selects the loading schedule through AXI4-Lite configuration bit
`conv_1x1` before each activation or weight command. No FPGA fabric
reconfiguration is needed when a layer changes convolution window size.

## Files

- `user_design/combined_1x1_3x3_dma/combined_hwc_channel_dma_agu.sv` — shared
  1x1/3x3 address generator.
- `user_design/combined_1x1_3x3_dma/dma_a.v` — drop-in AXI4-Lite wrapper; the
  existing `dma_a` module name
  and all existing ports are preserved.
- `Test/combined_1x1_3x3_dma/tb_combined_dma.sv` — self-contained exhaustive
  DMA regression.
- `Test/combined_1x1_3x3_dma/tb_npu_yolo_combined_1x1_integrated.sv` — combined DMA + actual NPU
  regression for the 1x1 workload.
- `Test/combined_1x1_3x3_dma/tb_npu_yolo_combined_3x3_integrated.sv` — combined DMA + actual NPU
  regression for the 3x3 workload.
- `Test/combined_1x1_3x3_dma/tb_npu_yolo_combined_sequential_integrated.sv` — one-reset,
  same-instance regression that computes the complete 3x3 workload, switches
  AXI configuration bit 9, and then computes the complete 1x1 workload on the
  same DMA, NPU, activation SRAMs, and psum SRAMs.
- `Test/combined_1x1_3x3_dma/check_reference_schedules.py` — simulator-independent comparison of
  the shared-FSM schedules with the supplied reference loop nests.
- `Test/combined_1x1_3x3_dma/Makefile.dma_combined` — simulation targets.

## AXI4-Lite programming model

The existing addresses are unchanged. Configuration bit 9 is new.

| Address | Access | Meaning |
| --- | --- | --- |
| `0x00` | W | Write source base address and start the configured operation. |
| `0x00` | R | Last accepted source base address. |
| `0x04` | R | `{error_sticky, busy, done_sticky}` in bits `[2:0]`. |
| `0x08` | W/R | Configuration register described below. |

Configuration register `0x08`:

| Bits | Field | Use |
| --- | --- | --- |
| `[0]` | `tile_x` | Activation tile x: 0 or 1. |
| `[1]` | `tile_y` | Activation tile y: 0 or 1. |
| `[2]` | `cin_block` | Input channels 0–7 or 8–15. |
| `[3]` | `load_weight` | 0 = activation, 1 = 8x8 weight slice. |
| `[4]` | `cout_block` | Output channels 0–7 or 8–15 for weights. |
| `[6:5]` | `kernel_y` | 3x3 weight tap y, 0–2. Ignored in 1x1 mode. |
| `[8:7]` | `kernel_x` | 3x3 weight tap x, 0–2. Ignored in 1x1 mode. |
| `[9]` | `conv_1x1` | 0 = 3x3 loading schedule, 1 = 1x1 loading schedule. |

Bit 9 resets to zero, so existing 3x3 CPU code remains backward-compatible.
Configuration writes and new starts are rejected with `SLVERR` while the DMA
is busy. A 3x3 weight start with `kernel_x` or `kernel_y` equal to 3 is also
rejected. Kernel fields are ignored in 1x1 mode.

Example control sequence:

```c
// 1x1 activation load for tile (tile_y, tile_x), input-channel block cin.
config = (1u << 9) | (cin << 2) | (tile_y << 1) | tile_x;
write32(DMA_BASE + 0x08, config);
write32(DMA_BASE + 0x00, image_base);  // starts the operation

// 3x3 weight load for one (ky,kx,cin,cout) 8x8 slice.
config = (kx << 7) | (ky << 5) | (cout << 4) | (1u << 3) | (cin << 2);
write32(DMA_BASE + 0x08, config);       // bit 9 = 0 selects 3x3
write32(DMA_BASE + 0x00, weight_base); // starts the operation
```

Poll status bit 0 (`done_sticky`) at `0x04`. Status bit 1 is `busy`, and bit 2
is `error_sticky`.

## Preserved loading contracts

An accepted `map_*` command still represents eight byte lanes.

- Activation lane `r` reads `map_source_addr + r`, then writes activation bank
  `r` at `map_buffer_addr`.
- A 1x1 activation start emits 256 commands for one 16x16 tile.
- A 3x3 activation start emits 324 commands for one 18x18 halo tile. Out-of-
  bounds halo commands assert `map_zero_fill` and require no external read.
- Weight lane/PE-row `r` reads
  `map_source_addr + r * map_source_stride`, where the stride is 16 bytes.
- Both weight modes emit output columns 7 through 0 in eight accepted commands,
  one disabled shift cycle, and then one `map_weight_swap` pulse.
- All map fields remain stable under backpressure.

## Placement in the existing repository

Place the two RTL files in `user_design/combined_1x1_3x3_dma/` and the
testbenches, Makefile, checker, and this README in
`Test/combined_1x1_3x3_dma/`. Add the two combined RTL files to the synthesis
source list in place of the standalone 1x1 or 3x3 DMA selected for that build.
The wrapper port list is unchanged, so `top_wrapper.v` and the downstream map
adapter do not need interface changes.

## Simulation commands

Run these from the root of `FABulous_demo_AXI_IO-main` after extracting the ZIP.

Self-contained exhaustive RTL regression:

```bash
make -f Test/combined_1x1_3x3_dma/Makefile.dma_combined clean
make -f Test/combined_1x1_3x3_dma/Makefile.dma_combined unit
```

Simulator-independent reference-schedule check:

```bash
make -f Test/combined_1x1_3x3_dma/Makefile.dma_combined model
```

Run all actual-NPU regressions using the existing NPU files under
`user_design/npu/` and memories under `Test/conv_1x1/` and `Test/conv_3x3/`.
This runs the isolated 1x1 and 3x3 integrated tests plus the same-instance
sequential transition test:

```bash
make -f Test/combined_1x1_3x3_dma/Makefile.dma_combined integrated
```

Run only the new 3x3-to-1x1 same-instance regression:

```bash
make -f Test/combined_1x1_3x3_dma/Makefile.dma_combined integrated-sequential
```

Or run the isolated integrated tests separately:

```bash
make -f Test/combined_1x1_3x3_dma/Makefile.dma_combined integrated-1x1
make -f Test/combined_1x1_3x3_dma/Makefile.dma_combined integrated-3x3
```

The sequential testbench contains exactly one `dma_a` and one
`npu_sram_wrapper` instance. It deasserts `rst_n` once, checks all 16,384 3x3
outputs, performs the CPU mode change through an AXI4-Lite configuration write,
and checks all 16,384 1x1 outputs without reasserting reset. The source vectors
for the two phases are independent; this validates the live hardware mode
transition rather than modeling a layer-to-layer data dependency.

If the memory filenames differ, override them on the command line:

```bash
make -f Test/combined_1x1_3x3_dma/Makefile.dma_combined integrated \
  CONV1_IMAGE_MEM=Test/conv_1x1/yolo_conv1_in.mem \
  CONV1_WEIGHTS_MEM=Test/conv_1x1/yolo_conv1_w.mem \
  CONV1_GOLDEN_MEM=Test/conv_1x1/golden_conv1.mem \
  CONV3_IMAGE_MEM=Test/conv_3x3/yolo_image_3x3.mem \
  CONV3_WEIGHTS_MEM=Test/conv_3x3/yolo_weights_3x3.mem \
  CONV3_GOLDEN_MEM=Test/conv_3x3/golden_conv3.mem
```

Direct `iverilog` commands for the self-contained regression:

```bash
mkdir -p Test/build/combined_1x1_3x3_dma
iverilog -g2012 -Wall -s tb_combined_dma \
  -o Test/build/combined_1x1_3x3_dma/tb_combined_dma.vvp \
  user_design/combined_1x1_3x3_dma/combined_hwc_channel_dma_agu.sv \
  user_design/combined_1x1_3x3_dma/dma_a.v \
  Test/combined_1x1_3x3_dma/tb_combined_dma.sv
vvp Test/build/combined_1x1_3x3_dma/tb_combined_dma.vvp
```

The unit regression is expected to end with:

```text
PASS: combined DMA matches all 1x1 and 3x3 loading schedules
```

The same-instance integrated regression is expected to end with:

```text
PASS: complete 3x3 then 1x1 workloads ran on one DMA/NPU/SRAM instance without reset
```
