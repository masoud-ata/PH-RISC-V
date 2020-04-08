# PH-RISC-V
A simple 32-bit 5-stage RISC-V processor in VHDL based on the book Computer Organization and Design by Patterson &amp; Hennesy.

For more information you can check out the book:
[here](https://www.amazon.com/gp/product/0128122757/ref=dbs_a_def_rwt_bibl_vppi_i2).

# Getting Started

The processor implements simple instructions such as lw, sw, add, sub, and, or. At this moment it supports forwarding, but lacks hazard detection and flushing capabilities.

It is fully synthesizable, and to demostrate functionalty the program memory is loaded with binary code that calulcates the fibonacci series to the 14th element and stores elements 13th and 14th to the data memory.

![fib](https://user-images.githubusercontent.com/54315689/78827646-b9cd5480-79e3-11ea-9799-987ccbeec5f5.png)

To understand the binary code you can check out the assembly code in the file fibonacci.rvi, and if you are interested you can use the following assmbler to modify the assembly code and generate the binary sequence to feed into the program memory (instruction_mem.mem file located in the design directory):
https://github.com/metastableB/RISCV-RV32I-Assembler

## Dependencies
Just add the files in the design directory to the source list of your sythesis tool (e.g. Xilinx Vivado) and you're good to go.
