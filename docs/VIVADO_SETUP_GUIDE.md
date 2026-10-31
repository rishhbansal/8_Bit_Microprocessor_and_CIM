# Vivado Installation & Usage Guide for Beginners
## Complete Walkthrough for the 8-Bit Pipelined RISC Microprocessor

This guide will walk you through downloading, installing, and using **AMD/Xilinx Vivado ML** to simulate, synthesize, and inspect waveforms for this SystemVerilog project.

---

## 1. Downloading & Installing Vivado

### Step 1: Download the Free Web Installer
1. Visit the AMD Xilinx Downloads page: [AMD Vivado ML Editions](https://www.xilinx.com/support/download.html).
2. Look for **Vivado ML Standard Edition** (Free / WebPACK, requires **no license**).
3. Download the **Xilinx Unified Installer for Windows** (Self-Extracting Web Installer, ~200 MB).
4. Create a free AMD account if prompted to begin the download.

### Step 2: Storage Saving Installation Tip (CRITICAL!)
By default, Vivado tries to install support for massive aerospace and enterprise FPGAs (Versal, UltraScale+), which can take **120+ GB of disk space**. 

To install only what you need (~35 GB total):
1. Run the installer and sign in with your AMD account.
2. Select **Vivado** (not Vitis or Lab Edition).
3. On the edition screen, select **Vivado ML Standard** (Free).
4. **On the Device Selection screen:**
   * **Uncheck** Versal ACAP
   * **Uncheck** UltraScale & UltraScale+
   * **Check ONLY**: **7 Series** (Artix-7, Spartan-7, Kintex-7) and **Zynq-7000**.
5. Select destination directory (e.g. `C:\Xilinx`) and finish installation.

---

## 2. Opening & Running the Project via Tcl (One-Click Setup)

Vivado provides a built-in Tcl console that can configure the entire project in 10 seconds without manual clicking:

1. Open **Vivado 202X.X** from your Windows Start Menu.
2. At the bottom of the Vivado home screen, find the **Tcl Console** tab.
3. Run the following two commands (adjust path to your project folder):
   ```tcl
   cd {c:/Users/Rishabh/Documents/antigravity/resilient-lovelace/scripts}
   source vivado_project.tcl
   ```
4. Vivado will automatically:
   * Create the project `pipelined_8bit_cpu`
   * Import all 10 SystemVerilog RTL files
   * Import `tb_cpu.sv` and `program.mem`
   * Configure compile order and target language to SystemVerilog.

---

## 3. Step-by-Step GUI Walkthrough (Manual Method)

If you prefer using the graphical user interface:

### Step 1: Create New Project
1. Click **File -> Project -> New...**
2. Project Name: `pipelined_8bit_cpu`
3. Project Type: **RTL Project** (check *Do not specify sources at this time* or proceed to add sources).
4. Default Part: Select `xc7a35tcpg236-1` (the popular Digilent Basys 3 Artix-7 FPGA).

### Step 2: Add SystemVerilog RTL Sources
1. In Flow Navigator, click **Add Sources** -> **Add or create design sources**.
2. Click **Add Files** and select all files from `resilient-lovelace/rtl/*.sv`.
3. In the Sources window, right-click any `.sv` file, select **Set File Type**, and ensure it is set to **SystemVerilog**.
4. Set `cpu_top.sv` as Top Module (Right-click `cpu_top.sv` -> **Set as Top**).

### Step 3: Add Simulation Testbench
1. Click **Add Sources** -> **Add or create simulation sources**.
2. Click **Add Files** and select:
   * `resilient-lovelace/tb/tb_cpu.sv`
   * `resilient-lovelace/sim/program.mem`
3. Right-click `tb_cpu.sv` -> **Set as Top**.

---

## 4. Running Behavioral Simulation & Waveforms

1. In the **Flow Navigator** (left sidebar), under **Simulation**, click **Run Simulation -> Run Behavioral Simulation**.
2. Vivado will compile the SystemVerilog code and open the Vivado Simulator waveform window.
3. **Navigating Waveforms:**
   * Press **F** (Zoom to Fit) to view the entire simulation run from 0 to 500 ns.
   * To add internal pipeline signals:
     In the **Scope** hierarchy window, expand `tb_cpu -> dut -> u_core`.
     Select signals (e.g. `pc`, `alu_result`, `stall`, `fwd_a`, `fwd_b`, `branch_taken`, `wb_data`).
     Right-click -> **Add to Wave Window**.
   * Click **Restart** (blue arrow with rewind) and **Run All** (play icon with sheet).
   * Right-click any signal in the waveform window -> **Radix** -> **Hexadecimal** or **Unsigned Decimal**.

4. **Observing the Console Output:**
   Look at the **Tcl Console** tab at the bottom. You will see our testbench logs reporting cycle-by-cycle execution and:
   ```
   ==================================================================
     >>> ALL CHECKS PASSED SUCCESSFULLY! (0 ERRORS) <<<
     Pipeline latency, forwarding, stalls, and ISA verified!
   ==================================================================
   ```

---

## 5. Running RTL Synthesis

Synthesis translates your SystemVerilog behavioral description into actual FPGA logic gates (Look-Up Tables, Flip-Flops, Multiplexers, Block RAMs).

1. In the Flow Navigator, under **Synthesis**, click **Run Synthesis**.
2. When synthesis finishes, select **Open Synthesized Design**.
3. **Inspect the Schematic:**
   * Click **Schematic** in the Synthesis window to see the visual gate-level and block-level diagram of your 5 pipeline stages!
4. **Inspect Resource Utilization:**
   * Click **Report Utilization** in the left panel.
   * You will see the exact count of:
     * **Slice LUTs**: ~120 - 200 LUTs (ALU, decoder, forwarding muxes)
     * **Slice Registers (FFs)**: ~150 - 250 FFs (pipeline stage registers and register file)
     * **BRAM / Distributed RAM**: Instruction and Data memories.
5. **Inspect Timing:**
   * Vivado reports Worst Negative Slack (WNS) and maximum estimated frequency ($F_{max} > 150\text{ MHz}$).
