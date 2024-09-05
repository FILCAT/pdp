// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {MerkleProof} from "../src/Proofs.sol";
import {BitOps} from "../src/BitOps.sol";
import {Hashes} from "../src/Proofs.sol";
 
contract MerkleProofTest is Test {

    function testVerifyEmptyProof() public view {
        bytes32 root = sha256("hello");
        bytes32[] memory proof = new bytes32[](0);
        bool result = MerkleProof.verify(proof, root, root);
        assertEq(result, true, "Verify should return true");
    }

    function testVerifyTreeTwoLeaves() public view {
        bytes32[] memory leaves = generateLeaves(2);
        bytes32[][] memory tree = buildMerkleTree(leaves);
        bytes32 root = tree[0][0];

        for (uint i = 0; i < leaves.length; i++) {
            bytes32[] memory proof = buildProof(tree, i);
            bool result = MerkleProof.verify(proof, root, leaves[i]);
            assertEq(result, true, string.concat("Invalid proof for leaf ", vm.toString(i)));
        }
    }

    function testVerifyTreeThreeLeaves() public view {
        bytes32[] memory leaves = generateLeaves(3);
        bytes32[][] memory tree = buildMerkleTree(leaves);
        bytes32 root = tree[0][0];

        for (uint i = 0; i < leaves.length; i++) {
            bytes32[] memory proof = buildProof(tree, i);
            bool result = MerkleProof.verify(proof, root, leaves[i]);
            assertEq(result, true, string.concat("Invalid proof for leaf ", vm.toString(i)));
        }
    }


    function testVerifyTreesManyLeaves() public view {
        for (uint256 width = 1; width < 100; width++) {
            bytes32[] memory leaves = generateLeaves(width);
            bytes32[][] memory tree = buildMerkleTree(leaves);
            bytes32 root = tree[0][0];

            // Verify proof for each leaf
            for (uint256 i = 0; i < leaves.length; i++) {
                bytes32[] memory proof = buildProof(tree, i);
                bool result = MerkleProof.verify(proof, root, leaves[i]);
                assertEq(result, true, string.concat("Invalid proof for leaf ", vm.toString(i)));
            }
        }
    }

    ///// Helper functions /////

    function generateLeaves(uint256 count) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = bytes32(i);
        }
        return result;
    }

    // Builds a merkle tree from an array of leaves.
    // The tree is an array of arrays of bytes32.
    // The last array is the leaves, and each prior array is the result of the commutative hash of pairs in the previous array.
    // An unpaired element is simply copied to the next level.
    // The first element of the first array is the root.
    function buildMerkleTree(bytes32[] memory leaves) internal view returns (bytes32[][] memory) {
        require(leaves.length > 0, "Leaves array must not be empty");

        uint256 levels = 256 - BitOps.clz(leaves.length - 1);
        bytes32[][] memory tree = new bytes32[][](levels + 1);
        tree[levels] = leaves;

        for (uint256 i = levels; i > 0; i--) {
            bytes32[] memory currentLevel = tree[i];
            uint256 nextLevelSize = (currentLevel.length + 1) / 2;
            tree[i - 1] = new bytes32[](nextLevelSize);

            for (uint256 j = 0; j < nextLevelSize; j++) {
                if (2 * j + 1 < currentLevel.length) {
                    tree[i - 1][j] = Hashes.commutativeHash(currentLevel[2 * j], currentLevel[2 * j + 1]);
                } else {
                    tree[i - 1][j] = currentLevel[2 * j];
                }
            }
        }

        return tree;
    }

    // Gets an inclusion proof from a Merkle tree for a leaf at a given index.
    // The proof is constructed by traversing up the tree to the root, and the sibling of each node is appended to the proof.
    // There is no sibling for an unpaired element, so it is not included in the proof, which thus is shorter than the tree height.
    function buildProof(bytes32[][] memory tree, uint256 index) internal pure returns (bytes32[] memory) {
        require(index < tree[tree.length - 1].length, "Index out of bounds");

        bytes32[] memory proof = new bytes32[](tree.length - 1);
        uint256 proofIndex = 0;

        for (uint256 i = tree.length - 1; i > 0; i--) {
            uint256 levelSize = tree[i].length;
            uint256 pairIndex = index ^ 1; // XOR with 1 to get the pair index

            if (pairIndex < levelSize) {
                proof[proofIndex] = tree[i][pairIndex];
                proofIndex++;
            }

            index /= 2; // Move to the parent node
        }
        // Trim proof to the correct length, from proofIndex.
        bytes32[] memory trimmedProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            trimmedProof[i] = proof[i];
        }
        return trimmedProof;
    }

    function printTree(bytes32[][] memory tree) internal pure {
        console.log("Tree:");
        for (uint i = 0; i < tree.length; i++) {
            console.log("Level ", i, ":");
            for (uint j = 0; j < tree[i].length; j++) {
                console.log(vm.toString(j), vm.toString(tree[i][j]));
            }
        }
        console.log();
    }

    function printProof(bytes32[] memory proof) internal pure {
        console.log("Proof: ");
        for (uint j = 0; j < proof.length; j++) {
            console.log(vm.toString(j), vm.toString(proof[j]));
        }
    }
}

contract HashesTest is Test {
    // Tests that the efficient hash function returns the same result as the expected hash function.
    function testHash() public view {
        bytes32 a = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        bytes32 b = bytes32(0x0000000000000000000000000000000000000000000000000000000000000001);
        verifyHash(a, a);
        verifyHash(a, b);
        verifyHash(b, a);
    }

    function verifyHash(bytes32 a, bytes32 b) internal view {
        bytes32 expected = expectedHash(a, b);
        bytes32 result = Hashes.commutativeHash(a, b);
        assertEq(result, expected, "Hashes.commutativeHash should return the expected hash");
    }

    // Implements commutative SHA256 hash of pairs via the standard sha256(abi.encode(a, b)).
    function expectedHash(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        bytes memory payload = a < b ? abi.encodePacked(a, b) : abi.encodePacked(b, a);
        return sha256(payload);
    }

}