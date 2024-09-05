// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Library for bit operations.
library BitOps {
    // Calculates the number of leading zeros in binary representation.
    function clz(uint256 x) internal pure returns (uint256) {
        uint256 n = 256;
        uint256 y;

        y = x >> 128; if (y != 0) { n -= 128; x = y; }
        y = x >> 64;  if (y != 0) { n -= 64;  x = y; }
        y = x >> 32;  if (y != 0) { n -= 32;  x = y; }
        y = x >> 16;  if (y != 0) { n -= 16;  x = y; }
        y = x >> 8;   if (y != 0) { n -= 8;   x = y; }
        y = x >> 4;   if (y != 0) { n -= 4;   x = y; }
        y = x >> 2;   if (y != 0) { n -= 2;   x = y; }
        y = x >> 1;   if (y != 0) return n - 2;
        return n - x;
    }
}