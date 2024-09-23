// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Cids {
    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329836995 
    struct Cid {
        bytes data;
    }

    function digestFromCid(Cid memory cid) public pure returns (bytes32) {
        require(cid.data.length >= 32, "Cid data is too short");
        // bytes memory dataSlice = new bytes(32);
        // Assembly version of
        // for (uint i = 0; i < 32; i++) {
        //     dataSlice[i] = cid.data[cid.data.length - 32 + i];
        // }
        // return bytes32(dataSlice);   
        assembly {
            // Allocate memory for the data slice.
            // Set dataSclice to the next 32-byte aligned location after the free memory pointer (at 0x40).
            let dataSlice := add(mload(0x40), 0x20)
            // Update free memory pointer to next slot after dataSlice.
            mstore(0x40, add(dataSlice, 0x20))

            // Copy the last 32 bytes from cid.data to dataSlice.
            // Load the length of cid.data (length is the first word in an array memory layout).
            let dataLength := mload(mload(cid))
            // Calculate starting position of the last 32 bytes in cid.data.
            let dataStart := add(mload(cid), sub(dataLength, 32))
            // Copy 32 bytes (one word) from dataStart into dataSlice.
            mstore(dataSlice, mload(dataStart))

            // Return the 32-byte slice as bytes32.
            // Store the data slice at 0x0 (an unused memory word).
            mstore(0x0, mload(dataSlice))
            // Return the 32 bytes at Ox0 as a bytes32.
            return(0x0, 0x20)
        }
    }
}