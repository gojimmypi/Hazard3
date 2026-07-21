# Allow extra time for the slow ULX3S FTDI-based JTAG connection.
set remotetimeout 30

# Prevent startup scripts from stopping for interactive confirmation.
set confirm off

# Hazard3 exposes three hardware breakpoint triggers.
set remote hardware-breakpoint-limit 3

# This target configuration does not support hardware watchpoints.
set remote hardware-watchpoint-limit 0
set can-use-hw-watchpoints 0

# Confirm RISC-V in logs
show architecture

# Run this command only after GDB has connected to OpenOCD.
define hazard3-start
    monitor halt
    load
    set $pc = _start
    tbreak main
    continue
end

document hazard3-start
Halt Hazard3, load the current ELF, set the entry point, and run to main.
end