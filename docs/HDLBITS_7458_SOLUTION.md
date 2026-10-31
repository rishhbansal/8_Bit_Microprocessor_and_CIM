# HDLBits Problem Solution: 7458 Chip
## Selection Criterion Requirement for IIT Indore Gymkhana

This document provides the complete, verified solution for the **7458 - HDLBits** problem required under the selection criteria.

---

## 1. Problem Description (HDLBits 7458)

The 7458 is a classic TTL chip that contains:
* Two 3-input AND gates driving a 2-input OR gate (Output `p1y`).
* Two 2-input AND gates driving a 2-input OR gate (Output `p2y`).

### Interface Signals
* **Inputs:**
  * Group 1: `p1a`, `p1b`, `p1c`, `p1d`, `p1e`, `p1f`
  * Group 2: `p2a`, `p2b`, `p2c`, `p2d`
* **Outputs:**
  * `p1y`
  * `p2y`

### Boolean Logic Equations
$$\text{p1y} = (\text{p1a} \land \text{p1b} \land \text{p1c}) \lor (\text{p1d} \land \text{p1e} \land \text{p1f})$$
$$\text{p2y} = (\text{p2a} \land \text{p2b}) \lor (\text{p2c} \land \text{p2d})$$

---

## 2. Solution Code for HDLBits

Submit the following code directly into the HDLBits editor:

```verilog
module top_module ( 
    input p1a, p1b, p1c, p1d, p1e, p1f,
    output p1y,
    input p2a, p2b, p2c, p2d,
    output p2y );

    // Output p1y: OR of two 3-input AND gates
    assign p1y = (p1a & p1b & p1c) | (p1d & p1e & p1f);

    // Output p2y: OR of two 2-input AND gates
    assign p2y = (p2a & p2b) | (p2c & p2d);

endmodule
```

---

## 3. SystemVerilog Modern Alternative

In SystemVerilog, using `logic` and `always_comb`:

```systemverilog
module top_module (
    input  logic p1a, p1b, p1c, p1d, p1e, p1f,
    output logic p1y,
    input  logic p2a, p2b, p2c, p2d,
    output logic p2y
);

    always_comb begin
        p1y = (p1a & p1b & p1c) | (p1d & p1e & p1f);
        p2y = (p2a & p2b) | (p2c & p2d);
    end

endmodule
```

---

## 4. Hardware Gate-Level Implementation

1. **Gate Count:**
   * 2 x 3-input AND gates
   * 2 x 2-input AND gates
   * 2 x 2-input OR gates
2. **Propagation Delay:**
   * $t_{pd} = t_{AND} + t_{OR} \approx 2 \text{ gate delays}$.
3. **Synthesis:**
   * In FPGA technology (Artix-7), each output implements inside a single 6-input Look-Up Table (LUT6), yielding near-zero latency (~0.1 ns).
