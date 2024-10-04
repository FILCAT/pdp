// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Cids {
    // Errors
    error CidDataTooShort();
    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329836995

    struct Cid {
        bytes data;
    }

    // Returns the last 32 bytes of a CID payload as a bytes32.
    function digestFromCid(Cid memory cid) internal pure returns (bytes32 result) {
        if (cid.data.length < 32) revert CidDataTooShort();

        assembly {
            // Get the pointer to the cid.data bytes array
            let dataPtr := mload(cid) // Points to the start of cid.data (bytes array)
            let dataLength := mload(dataPtr) // Length of cid.data
            let dataStart := add(dataPtr, 0x20) // Start of the actual data in cid.data

            // Calculate the position of the last 32 bytes
            let digestPtr := add(dataStart, sub(dataLength, 32))

            // Load the digest from the calculated position
            result := mload(digestPtr)
        }
    }

    // Makes a CID from a prefix and a digest.
    // The prefix doesn't matter to these contracts, which only inspect the last 32 bytes (the hash digest).
    function cidFromDigest(bytes memory prefix, bytes32 digest) internal pure returns (Cids.Cid memory) {
        bytes memory byteArray = new bytes(prefix.length + 32);
        for (uint256 i = 0; i < prefix.length; i++) {
            byteArray[i] = prefix[i];
        }
        for (uint256 i = 0; i < 32; i++) {
            byteArray[i+prefix.length] = bytes1(digest << (i * 8));
        }
        return Cids.Cid(byteArray);
    }
}