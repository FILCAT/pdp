// SPDX-License-Identifier: MIT
// Adapted from OpenZeppelin Contracts (last updated v5.0.0) (utils/cryptography/MerkleProof.sol)
// Changes:
// - Specialised to hash function of SHA256
// - Removed unused functions, incl multiproofs
// - Remove redundant comments and cruft

pragma solidity ^0.8.20;

/**
 * These functions deal with verification of Merkle Tree proofs.
 *
 * They are specialised to the hash function of SHA256.
 */
library MerkleProof {
    /**
     * Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root` at `position`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree.
     *
     * This version handles proofs in memory.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf, uint256 position) internal view returns (bool) {
        return processProofMemory(proof, leaf, position) == root;
    }

    /**
     * Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` at `position` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree.
     *
     * This version handles proofs in memory.
     */
    function processProofMemory(bytes32[] memory proof, bytes32 leaf, uint256 position) internal view returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            // If position is even, the leaf/node is on the left and sibling is on the right.
            bytes32 sibling = proof[i];
            if (position % 2 == 0) {
                computedHash = Hashes.orderedHash(computedHash, sibling);
            } else {
                computedHash = Hashes.orderedHash(sibling, computedHash);
            }
            position /= 2;
        }
        return computedHash;
    }

    /**
     * Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root` at `position`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree.
     *
     * This version handles proofs in calldata.
     */
    function verifyCalldata(bytes32[] calldata proof, bytes32 root, bytes32 leaf, uint256 position) internal view returns (bool) {
        return processProofCalldata(proof, leaf, position) == root;
    }

    /**
     * Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` at `position` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree.
     *
     * This version handles proofs in calldata.
     */
    function processProofCalldata(bytes32[] calldata proof, bytes32 leaf, uint256 position) internal view returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            // If position is even, the leaf/node is on the left and sibling is on the right.
            bytes32 sibling = proof[i];
            if (position % 2 == 0) {
                computedHash = Hashes.orderedHash(computedHash, sibling);
            } else {
                computedHash = Hashes.orderedHash(sibling, computedHash);
            }
            position /= 2;
        }
        return computedHash;
    }
}

library Hashes {
    /** Order-dependent hash of pair of bytes32. */
    function orderedHash(bytes32 a, bytes32 b) internal view returns (bytes32) {
        return _efficientSHA256(a, b);
    }


    /** Implementation of sha256(abi.encode(a, b)) that doesn't allocate or expand memory. */
    function _efficientSHA256(bytes32 a, bytes32 b) private view returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            
            // Call the SHA256 precompile
            if iszero(staticcall(gas(), 0x2, 0x00, 0x40, 0x00, 0x20)) {
                revert(0, 0)
            }
            
            value := mload(0x00)
        }
    }
}