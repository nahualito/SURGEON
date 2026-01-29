#include <surgeon/runtime.h>
#include <stdio.h>

void __attribute__((constructor)) surgeon_setup(void) {
    // Correct function call: map_rw_region(ADDRESS, SIZE)
    
    // Map the Peripherals region (Address 0x40000000, Size 0x10000)
    if (map_rw_region(0x40000000, 0x10000) != SUCCESS) {
        fprintf(stderr, "[FATAL] Failed to map PERIPHERALS_1\n");
    }

    // Map the SRAM Bitband region (Address 0x20000000, Size 0x10000)
    if (map_rw_region(0x20000000, 0x10000) != SUCCESS) {
        fprintf(stderr, "[FATAL] Failed to map SRAM_BITBAND\n");
    }
}
