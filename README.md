# 8-Bit Pipelined RISC Microprocessor & Optical Ising Machine (CIM) Physical Design

An advanced, synthesizable **8-bit 5-stage pipelined RISC microprocessor** designed in modern **SystemVerilog (IEEE 1800-2012/2017)**, featuring dual ASIC physical implementation flows on **SkyWater 130nm (`sky130_fd_sc_hd`)**:
1. **Classical EDA Flow:** Synthesized and routed via OpenLane / OpenROAD (Yosys + FastRoute + TritonRoute).
2. **Quantum/Optical Ising Machine (CIM) Accelerated Flow:** NP-hard Global Routing mapped to a Quadratic Unconstrained Binary Optimization (QUBO) Hamiltonian and solved on an **Optical Ising Computer**, translated to physical route guides, detailed routed, and streamed out to a separate GDSII layout.

---

## 1. Microprocessor Architectural Features

* **5-Stage Pipeline:** Instruction Fetch (`IF`), Instruction Decode (`ID`), Execute (`EX`), Memory Access (`MEM`), and Write-Back (`WB`).
* **Harvard Architecture:** Segregated 256-word instruction memory and 256-byte data memory to eliminate memory structural hazards.
* **Custom 16-Bit Fixed ISA:**
  * Immediate loading (`LDI Rd, Imm8`).
  * Register-to-register arithmetic and logic (`ADD`, `SUB`, `AND`, `OR`, `XOR`).
  * Barrel shifter supporting both **Logical Shift Right (`SRL`)** and **Signed Arithmetic Shift Right (`SRA`)**.
  * Signed vs. unsigned comparisons (`SLT` vs. `SLTU`).
  * Base-plus-offset memory load/store (`LD`, `ST`).
  * Control flow: Conditional branches (`BEQ`, `BNE`, `BLT`, `BGE`) and unconditional jumps (`JMP`, `JAL`, `JR`).
* **Hazard Mitigation Strategies:**
  * **RAW Data Forwarding:** Dedicated EX-to-EX and MEM-to-EX forwarding networks eliminate stalls for data dependencies.
  * **Load-Use Interlock:** Hardware hazard unit freezes PC and IF/ID while injecting a 1-cycle bubble (flush) into ID/EX when an instruction immediately consumes a `LD` target.
  * **Branch Penalty Mitigation:** Branch outcome evaluated in EX stage; taken branches flush wrong-path instructions (2-cycle penalty), while not-taken branches incur 0 penalties.

---

## 2. Quantum / Optical Ising Machine (CIM) Global Routing

In standard VLSI physical design, **Global Routing** is an NP-hard combinatorial optimization problem that finds Steiner tree routing paths across a uniform tile grid without exceeding edge capacities. 

In this project, global routing for the `cpu_core` was formulated into an Ising spin Hamiltonian / QUBO problem and solved directly on an **Optical Coherent Ising Machine (CIM)**.

```
+------------------+      +--------------------+      +-----------------------+
|  Placed Core     | ---> | QUBO Formulation   | ---> | Optical Ising Machine |
|  Def & Netlist   |      | 991 Binary Spins   |      | Coherent OPO Cavity   |
+------------------+      | (qio_full_chip_v2) |      +-----------------------+
                                                                  |
                                                                  v
+------------------+      +--------------------+      +-----------------------+
|  Alternative     | <--- | TritonRoute        | <--- | Spin to Guide Parser  |
|  GDSII Layout    |      | Detailed Routing   |      | (cim_routes.guide)    |
+------------------+      +--------------------+      +-----------------------+
```

### Problem Formulation & Mathematical Modeling
Let binary variable $x_{i,k} \in \{0, 1\}$ represent whether net $i$ chooses candidate routing tree topology $k$ across global routing grid edges $e \in E$:

$$H_{\text{QUBO}} = \sum_{i} \sum_{k} w_{i,k} x_{i,k} + \alpha \sum_{i} \left( 1 - \sum_{k} x_{i,k} \right)^2 + \beta \sum_{e \in E} \max\left(0, \sum_{(i,k) \in e} x_{i,k} - C_e\right)^2$$

* **Linear Term:** Minimizes total wirelength $w_{i,k}$ and via penalties.
* **Unicity Constraint ($\alpha$):** Enforces that exactly one valid tree topology is selected per net.
* **Capacity Constraint ($\beta$):** Heavily penalizes tile edge overflow where demand exceeds maximum metal layer routing capacity $C_e$.

### Hardware Execution Metrics (`result_full.json`)
The resulting graph was compiled into upper-triangular matrix form (`qio_full_chip_v2.json`) and dispatched to the optical computing cluster:

| Parameter | Value | Description |
| :--- | :--- | :--- |
| **Job Identifier** | `job_ecc3ad3e3fff15d1` | Hardware execution run ID |
| **Hardware Mode** | `OPTICAL_HARDWARE` | Physical optical Ising machine |
| **Problem Type** | `QUBO` | Quadratic Unconstrained Binary Optimization |
| **Variable Count ($N$)** | **991 spins** | Binary decision variables |
| **Sample Shots** | 40 | Independent optical cavity anneal trajectories |
| **Ground Energy** | **-4088.0** | Lowest Hamiltonian energy eigenvalue reached |
| **Hardware Time** | **2342.86 ms (~2.34 s)** | Pure optical solve time across 40 shots |

### Route Guide Reconstruction & Detailed Routing
The 991-spin binary ground-state solution was mapped back to 3D rectangular bounding box metal tracks (`met1`–`met5`) in OpenROAD guide format:
* **Output Guide:** `cim_run_globalrouting/cim_routes.guide` (15,545 routing box declarations).
* **Detailed Routing:** Driven through TritonRoute via `designs/cpu_core/run_cim_droute.tcl`.
* **GDSII Streamout & DRC:** Merged with Sky130 standard cell layouts in Magic with **0 DRC violations**, producing a valid alternative tapeout layout.

---

## 3. Deep-Dive: Why Did the Optical Computer Take More Time Than the Classical CPU?

A central question in non-von-Neumann computing: **Why did the optical computer require ~2.34 seconds, whereas classical FastRoute on a standard x86 CPU executed in ~1.42 seconds?**

1. **The Scale Crossover Point ($N = 991$ vs. Asymptotic Speedup):**
   * Optical Ising machines exploit quantum-inspired coherence and continuous-time nonlinear dissipation to achieve polynomial/sub-exponential scaling on NP-hard search spaces.
   * However, for an 8-bit core with **991 variables**, the problem size sits well below the crossover threshold where classical algorithms suffer combinatorial explosion.
   * Classical heuristics (A*-maze routing and rip-up-and-reroute in C++) run in $O(N \log N)$ average time for small sparse graphs and fit entirely within **L1/L2 CPU cache** with near-zero latency.
2. **Electronic-Optical Transduction & Interface Overhead:**
   * Before optical computation begins, the problem matrix must be serialized into digital packets, transmitted over high-speed interconnects (PCIe), converted via DACs to modulate optical pump pulses, and read back via photodiodes and ADCs.
   * In contrast to an on-chip CPU memory bus, the I/O setup and measurement round-trips dominate the 2.34 s runtime.
3. **Planar Sparsity vs. All-to-All Optical Topologies:**
   * VLSI global routing graphs are planar and spatially sparse (cells interact only with adjacent tiles).
   * Coherent Ising Machines are physically engineered to excel at **dense, all-to-all coupled spin graphs** (e.g., MAX-CUT, Dense TSP). Mapping a sparse geometric grid onto an all-to-all optical coupling matrix incurs penalty overheads and slack variables that increase the required annealing time.

> [!NOTE]
> The optical advantage emerges when scaling to multi-million-gate SoCs ($N > 10^5 \text{ to } 10^6$), where classical rip-up-and-reroute runtimes scale to days or fail to converge, while optical relaxation scales substantially flatter.

---

## 4. Directory Structure

```
8_Bit_Microprocessor_and_CIM/
├── rtl/                                # SystemVerilog Synthesizable RTL
│   ├── cpu_pkg.sv                      # Package: opcodes, enums, pipeline structs
│   ├── alu.sv                          # 8-bit ALU with signed/unsigned arith & shifts
│   ├── reg_file.sv                     # 8x8 Register File (R0=0, write-before-read)
│   ├── control_unit.sv                 # 16-bit Instruction Decoder & Control logic
│   ├── hazard_unit.sv                  # RAW Forwarding & Load-Use Hazard Unit
│   ├── pipeline_regs.sv                # Synchronous IF/ID, ID/EX, EX/MEM, MEM/WB registers
│   ├── instruction_mem.sv              # 256-word Instruction ROM/RAM
│   ├── data_mem.sv                     # 256-byte Data RAM
│   ├── cpu_core.sv                     # Integrated 5-stage CPU Core
│   └── cpu_top.sv                      # Top-level SoC wrapper for FPGA
├── designs/                            # OpenLane Physical Design Directory
│   └── cpu_core/
│       ├── config.json                 # Modern OpenLane 2 configuration file
│       ├── constraints.sdc             # SDC Timing Constraints (50 MHz / 20 ns period)
│       ├── cim_routes.guide            # Optical Ising Machine generated routing guide
│       ├── run_cim_droute.tcl          # OpenLane script to detailed-route & streamout CIM layout
│       └── src/                        # Pure Verilog-2001 & SV sources for physical synthesis
├── cim_run_globalrouting/              # Optical Ising Global Routing Run Artifacts
│   ├── qio_full_chip_v2.json           # 991-variable serialized QUBO problem matrix
│   ├── result_full.json                # Optical hardware execution result (shots, spins, energy)
│   ├── cim_routes.guide                # Parsed FastRoute guide for TritonRoute
│   └── routing_benchmark_comparison.png# Classical vs. CIM benchmark visualization
├── sim/
│   ├── test_program.asm                # Comprehensive verification test program
│   ├── program.mem                     # Assembled hex machine code
│   ├── listing.txt                     # Assembly listing with line-by-line machine code
│   └── run_sim.py                      # Standalone cycle-accurate Python pipeline simulator
├── scripts/
│   ├── assemble.py                     # Custom 2-pass Python assembler
│   └── vivado_project.tcl              # Automated AMD Vivado project & synthesis script
├── docs/
│   ├── FIRST_PRINCIPLES_GUIDE.md       # Block-by-block explanation & hardware inference
│   ├── VIVADO_SETUP_GUIDE.md           # Vivado installation & simulation tutorial
│   ├── ISA_SPECIFICATION.md            # Complete Instruction Set Architecture reference
│   ├── PROJECT_PROPOSAL_REPORT.md      # Architecture proposal and timing analysis
│   ├── HDLBITS_7458_SOLUTION.md        # Solution for HDLBits 7458 circuit
│   └── BONUS_C_PROGRAM_MAPPING.md      # C benchmark program to assembly compilation
└── README.md
```

---

## 5. Verification & Simulation

### Instant Pipeline Verification (Cycle-Accurate Simulator)
Run the software simulator to verify all 50 execution cycles, hazards, branch penalties, and memory operations:
```powershell
python sim/run_sim.py
```

### Re-assembling Custom Machine Code
```powershell
python scripts/assemble.py sim/test_program.asm sim/program.mem sim/listing.txt
```

### AMD Vivado Simulation
```tcl
cd scripts
source vivado_project.tcl
launch_simulation
```

---

## 6. How to Re-Run the CIM Detailed Routing to GDSII

Inside your OpenLane Docker environment in WSL / Linux:
```bash
./flow.tcl -interactive
```
At the OpenLane `%` prompt:
```tcl
source /openlane/designs/cpu_core/run_cim_droute.tcl
```
This feeds the CIM guide into TritonRoute, streams out the GDSII with Magic, and verifies DRC cleanliness.
