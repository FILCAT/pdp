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
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     *
     * This version handles proofs in memory.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal view returns (bool) {
        return processProof(proof, leaf) == root;
    }

    /**
     * Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree. When processing the proof, the pairs
     * of leafs & pre-images are assumed to be sorted.
     *
     * This version handles proofs in memory.
     */
    function processProof(bytes32[] memory proof, bytes32 leaf) internal view returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = Hashes.commutativeHash(computedHash, proof[i]);
        }
        return computedHash;
    }

    /**
     * Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     *
     * This version handles proofs in calldata.
     */
    function verifyCalldata(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal view returns (bool) {
        return processProofCalldata(proof, leaf) == root;
    }

    /**
     * Returns the rebuilt hash obtained by traversing a Merkle tree up
     * from `leaf` using `proof`. A `proof` is valid if and only if the rebuilt
     * hash matches the root of the tree. When processing the proof, the pairs
     * of leafs & pre-images are assumed to be sorted.
     *
     * This version handles proofs in calldata.
     */
    function processProofCalldata(bytes32[] calldata proof, bytes32 leaf) internal view returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = Hashes.commutativeHash(computedHash, proof[i]);
        }
        return computedHash;
    }
}


library Hashes {
    /** Commutative hash of pair of bytes32. */
    function commutativeHash(bytes32 a, bytes32 b) internal view returns (bytes32) {
        return a < b ? _efficientSHA256(a, b) : _efficientSHA256(b, a);
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