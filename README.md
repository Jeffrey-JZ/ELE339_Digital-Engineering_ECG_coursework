# Feature Extraction by Sobel Filter Accelerator Based on RVfpga SoC

**Design of a RISC-V Based Custom Hardware Accelerator for Sobel Edge Detection Processing**

> Author: **Junze Jiang**

<p align="center">
  <img src="Image/lena_original.jpg" width="240">
  <img src="Image/edges_detected.png" width="240">
  <img src="Image/edges_from_fpga.png" width="240">
</p>
<p align="center">
  <em>(a) Original &nbsp;&nbsp;&nbsp; (b) CPU-only &nbsp;&nbsp;&nbsp; (c) Hardware accelerator</em>
</p>

---

## 📁 Repository Structure

```
Feature_Extraction_by_Sobel_Filter_Accelerator/
├── original_rvfpganexys.bit              # Bitstream: baseline reference SoC
├── accelerator_rvfpganexys.bit           # Bitstream: SoC + Sobel accelerator
│
├── original_sw/                          # Software for baseline SoC (cycle counting)
├── accelerator_sw/                       # Software for accelerator SoC
│                                         #   (counts cycles for both paths + golden compare)
│
├── RVFPGA_CodeDocs/src/SweRVolfSoC/Peripherals/SobelAccelerator/
│                                         # Accelerator HDL integrated into reference SoC
│
└── Accelerator_verilog_code/             # Standalone HDL + per-block testbenches
    ├── basic_ip.v
    ├── controlpath_engine.v
    ├── datapath_kernel_operation.v
    ├── pfb_addr_map.v
    ├── pfb_bank_ram.v
    ├── pfb_top.v
    ├── engine_pfb_top.v
    ├── dma_module.v
    ├── csr_wb.v
    ├── dma_csr_top.v
    └── sobel_acc_top.v
```
---

## 📖 Overview

This repository contains the complete source code, HDL, testbenches, and bitstreams for a custom hardware accelerator that performs **Sobel edge detection** within a RISC-V **SweRV EH1** system-on-chip (SoC), implemented on a **Xilinx Artix-7 100T** FPGA (Digilent Nexys A7).

The accelerator is integrated into the reference **RVfpga** SoC as a loosely coupled memory-mapped peripheral, communicating with the CPU through a **Wishbone slave bus** (control/status) and an **AXI4 master bus** (bulk data transfer).

### 🎯 Headline Results (128×128 image @ 50 MHz)

| Metric | CPU-only | With Accelerator | Improvement |
|---|---|---|---|
| **Cycle count** | 11,035,714 | 129,042 | **85.5× speedup** |
| **Execution time** | 220.71 ms | 2.58 ms | |
| **Throughput** | — | ~387 fps | |
| **LUT overhead** | — | +2,460 (+7.2%) | Target: < 20% ✅ |
| **DSP usage** | — | 0 | Shift-and-add only |
| **Accuracy vs SW** | — | **0 mismatches / 16384 px** | Bit-exact |

---

## ✨ Key Features

- **Loosely coupled integration** — no modifications to the verified EH1 processor pipeline
- **Three-stage pipelined Sobel engine** — 1 output pixel per clock cycle, 2-cycle latency
- **Multiplier-free datapath** — exclusively shift-and-add arithmetic, **zero DSP slices used**
- **Four-bank interleaved Private Frame Buffer (PFB)** — dual-port BRAM with per-bank combinational arbitration and read-return tagging
- **Autonomous AXI4 DMA engine** — 16-beat INCR bursts, LOAD / ENGINE / STORE FSM
- **Early-start mechanism** — Sobel engine triggers after only 3 image rows are loaded, overlapping data transfer with computation
- **Byte-exact golden-model verification** — 141 directed test cases across unit / integration / system levels

---

## 🧠 Sobel Edge Detection Background

The Sobel operator computes horizontal and vertical gradients across a 3×3 window:

```
        [-1  0  1]              [-1 -2 -1]
  Gx =  [-2  0  2]    Gy =      [ 0  0  0]
        [-1  0  1]              [ 1  2  1]
```

The gradient magnitude is approximated to avoid an expensive square-root:

$$M(x,y) = \sqrt{G_x^2 + G_y^2} \approx |G_x| + |G_y|$$

A programmable threshold (default = 60) classifies each pixel as edge or non-edge.

<p align="center">
  <table align="center" border="0" cellspacing="0" cellpadding="8">
    <tr>
      <!-- 左子图 (a) -->
      <td width="32%" align="center" valign="top">
        <img src="Image/Gradient_Theory.png" width="80%" alt="Sobel kernel locations">
        <br><br>
        <em>(a) A simple example of three different types of Sobel kernel locations</em>
      </td>
      <!-- 右子图 (b)：两张图堆叠 -->
      <td width="62%" align="center" valign="top">
        <img src="Image/kernel扫描.png" width="60%" alt="X and Y convolution kernels"><br><br>
        <img src="Image/sobel计算.png" width="100%" alt="Gradient calculation by shifting the kernel">
        <br><br>
        <em>(b) Calculating gradients by shifting the convolution kernel</em>
      </td>
    </tr>
  </table>
</p>

<p align="center">
  <strong><em>Figure 1:</em></strong> <em>Illustrations of kernel placement and gradient calculation</em>
</p>

---

## 🏗️ SoC Architecture

The accelerator is organised into two top-level subsystems:

- **DMA + CSR subsystem** — handles CPU configuration (Wishbone) and bulk data transfer (AXI4)
- **Engine + PFB subsystem** — performs the Sobel computation on on-chip BRAM

![SoC architecture block diagram](Image/architecture_block_diagram.png)

### Execution flow

1. CPU writes `SRC_BASE_ADDR`, `DST_BASE_ADDR`, `PIXEL_COUNT`, `THRESHOLD` via Wishbone.
2. CPU writes `CTRL[0] = 1` to issue a single-cycle start pulse.
3. DMA bursts the image from main memory → unpacks 64-bit beats → writes PFB byte-by-byte.
4. After 3 rows (384 pixels) are loaded, DMA pulses `engine_start`.
5. Sobel engine slides a 3×3 window, pipelines the gradient, writes results back in-place into the PFB.
6. DMA repacks processed pixels and bursts them back to main memory over AXI4.
7. CPU polls `STATUS.done` (or `STATUS.error`).

---

## 🔧 Hardware Design Details

### Sobel Engine

The engine consists of a **control-path FSM** (pixel addressing + sliding window) and a **three-stage pipelined datapath** (gradient → magnitude → threshold + clip).

![SoC Engine FSM](Image/Sobel_Engine_FSM.png)

The datapath uses only 19 combinational IP instances from `basic_ip.v`:

| IP Block | `left_shift_ip` | `signed_sub_ip` | `signed_add_ip` | `abs_ip` | `com_ip` | `clip_ip` | **Total** |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Count | 4 | 6 | 5 | 2 | 1 | 1 | **19** |

![Three-stage pipelined Sobel datapath schematic](Image/engine_datapath.png)

### Private Frame Buffer (PFB)

- **16,384 pixels** (128×128×8-bit) split across **4 BRAM banks** × 4,096 entries each
- **14-bit global address** → 2-bit bank selector (LSBs) + 12-bit local address
- **Dual-port** per bank → 8 ports total, arbitrated between DMA read/write and engine read/write
- **Read-return tagging** (`SRC_DMA_RD` / `SRC_ENG_RD`) routes one-cycle-latency BRAM reads back to the correct requester
- `wr_conflict` flag raised on same-bank, same-address simultaneous writes (DMA wins)

![Private frame buffer four-bank interleaved architecture](Image/pfb_schematic_diagram.png)


### DMA Module

A single FSM drives the full **LOAD → ENGINE → STORE** sequence over AXI4 with INCR bursts (max 16 beats, 64-bit words = 8 pixels per beat → 128 pixels per burst → 128 bursts per frame).

![DMA module finite state machine with LOAD, ENGINE, STORE phases](Image/dma_fsm.png)

---

## 🗂️ Control / Status Register Map

Base address: `0x80001600` (Wishbone slave)

| Register | Offset | Access | Function |
|---|---|:---:|---|
| `CTRL` | `0x00` | W | `[0]` start pulse, `[1]` clear done, `[2]` clear error |
| `SRC_BASE_ADDR` | `0x04` | R/W | DMA source address in main memory |
| `DST_BASE_ADDR` | `0x08` | R/W | DMA destination address in main memory |
| `PIXEL_COUNT` | `0x0C` | R/W | Total pixels to transfer (16,384 for 128×128) |
| `STATUS` | `0x10` | R | `[0]` busy, `[1]` done, `[2]` error |
| `THRESHOLD` | `0x14` | R/W | Sobel edge threshold (default 60) |

---

## 🧪 Software Algorithm Flow

The C + Python software stack:
1. **Python (Pillow)** — converts any colour image into a 128×128 greyscale matrix (`image_to_matrix.py`) and emits `image_data.h`.
2. **C (sobel.c)** — runs the Sobel algorithm on the EH1 core, dumps results to `edge_raw.txt` via UART.
3. **Python (NumPy + Matplotlib)** — visualises the dumped pixel data as an edge map (`view_edge.py`).

Cycle counts are measured using the SweRVolf `mtime` counter (free-running 64-bit timer @ `0x80001020`), bracketing `sobel_edge()` in software and the `start → done` polling window in hardware.

![DMA module finite state machine with LOAD, ENGINE, STORE phases](Image/sw流程图.png)

---

## ✅ Verification

A hierarchical **bottom-up** strategy with **141 directed test cases**, all passing:

| Level | Module Under Test | Cases |
|---|---|:---:|
| Unit | Basic IPs | 12 |
| Unit | Sobel Datapath | 6 |
| Unit | Sobel Engine | 9 |
| Unit | Private Frame Buffer | 13 |
| Unit | DMA Module | 17 |
| Unit | CSR Block | 21 |
| Integration | Engine + PFB | 18 |
| Integration | DMA + CSR | 25 |
| Top-level | Sobel Accelerator Top | 20 |
| | **Total** | **141** |

In addition, an on-board byte-by-byte comparison against the C software golden model confirmed **0 mismatches across all 16,384 pixels**.

---

## 📊 Results

### Timing (post-implementation, 50 MHz target)

| Metric | Original SoC | With Accelerator |
|---|---|---|
| WNS (setup) | 0.117 ns | 0.429 ns |
| Timing met | ✅ | ✅ |

The critical path remains within the EH1 CPU core — the accelerator does **not** degrade the operating frequency.

### FPGA Resource Utilisation (Artix-7 100T)

| Resource | Original | + Accelerator | Δ | Util. % |
|---|---:|---:|---:|---:|
| LUT  | 34,281 | 36,741 | **+2,460 (+7.2%)** | 57.9% |
| FF   | 19,114 | 22,586 | +3,472 (+18.2%) | 17.8% |
| BRAM | 44 | 48 | +4 (+9.1%) | 35.6% |
| DSP  | 4 | 4 | **0** | 1.7% |

### Visual result

<p align="center">
  <img src="Image/lena_original.jpg" width="240">
  <img src="Image/edges_detected.png" width="240">
  <img src="Image/edges_from_fpga.png" width="240">
</p>
<p align="center">
  <em>(a) Original &nbsp;&nbsp;&nbsp; (b) CPU-only &nbsp;&nbsp;&nbsp; (c) Hardware accelerator</em>
</p>

---

## 🚀 Getting Started

### Prerequisites

- **Digilent Nexys A7** board (Xilinx Artix-7 100T)
- **Xilinx Vivado** (WebPACK edition is sufficient)
- **PlatformIO** (for compiling the C firmware)
- **Python 3** with `Pillow`, `NumPy`, `Matplotlib`

### Quick flow

1. Flash one of the provided bitstreams:
   - `original_rvfpganexys.bit` for the CPU-only baseline
   - `accelerator_rvfpganexys.bit` for the accelerated SoC
2. Convert your input image with `image_to_matrix.py` (outputs `image_data.h`).
3. Build the firmware in `accelerator_sw/` using PlatformIO and upload.
4. Capture UART output → `edge_raw.txt`.
5. Visualise with `view_edge.py`.

---
