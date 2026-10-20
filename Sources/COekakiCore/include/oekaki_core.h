#ifndef OEKAKI_CORE_H
#define OEKAKI_CORE_H

#include <stdint.h>

// Implemented in core/core.kizu; see the comments there for the contract.
int64_t core_bucket_fill(
    const uint8_t *rgba, int32_t width, int32_t height,
    int32_t seed_x, int32_t seed_y, int32_t tolerance, int32_t gap,
    uint8_t *wall, uint8_t *thick, uint8_t *tmp,
    uint8_t *interior, uint8_t *full,
    int32_t *stack, int32_t *bbox);

#endif
