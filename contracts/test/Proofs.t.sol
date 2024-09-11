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
        bool result = MerkleProof.verify(proof, root, root, 0);
        assertEq(result, true, "Verify should return true");
    }

    function testVerifyTreeTwoLeaves() public view {
        bytes32[] memory leaves = generateLeaves(2);
        bytes32[][] memory tree = buildMerkleTree(leaves);
        bytes32 root = tree[0][0];

        for (uint i = 0; i < leaves.length; i++) {
            bytes32[] memory proof = buildProof(tree, i);
            assertTrue(MerkleProof.verify(proof, root, leaves[i], i), string.concat("Invalid proof ", vm.toString(i)));
            assertFalse(MerkleProof.verify(proof, root, leaves[i], i+1), string.concat("False proof ", vm.toString(i)));
        }
    }

    function testVerifyTreeThreeLeaves() public view {
        bytes32[] memory leaves = generateLeaves(3);
        bytes32[][] memory tree = buildMerkleTree(leaves);
        bytes32 root = tree[0][0];

        for (uint i = 0; i < leaves.length; i++) {
            bytes32[] memory proof = buildProof(tree, i);
            assertTrue(MerkleProof.verify(proof, root, leaves[i], i), string.concat("Invalid proof ", vm.toString(i)));
            // Ensure the proof is invalid for every other index within range
            for (uint j = 0; j < leaves.length; j++) {
                if (j != i) {
                    assertFalse(MerkleProof.verify(proof, root, leaves[i], j));
                }
            }
        }
    }


    function testVerifyTreesManyLeaves() public view {
        for (uint256 width = 4; width < 60; width++) {
            bytes32[] memory leaves = generateLeaves(width);
            bytes32[][] memory tree = buildMerkleTree(leaves);
            bytes32 root = tree[0][0];

            // Verify proof for each leaf
            for (uint256 i = 0; i < leaves.length; i++) {
                bytes32[] memory proof = buildProof(tree, i);
                assertTrue(MerkleProof.verify(proof, root, leaves[i], i), string.concat("Invalid proof ", vm.toString(i)));
                // Ensure the proof is invalid for every other index within range
                for (uint j = 0; j < leaves.length; j++) {
                    if (j != i) {
                        assertFalse(MerkleProof.verify(proof, root, leaves[i], j));
                    }
                }
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
    // An unpaired element is paired with itself to create the value at the next level up.
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
                    tree[i - 1][j] = Hashes.orderedHash(currentLevel[2 * j], currentLevel[2 * j + 1]);
                } else {
                    // Pair final odd node with itself.
                    tree[i - 1][j] = Hashes.orderedHash(currentLevel[2 * j], currentLevel[2 * j]);
                }
            }
        }

        return tree;
    }

    // Gets an inclusion proof from a Merkle tree for a leaf at a given index.
    // The proof is constructed by traversing up the tree to the root, and the sibling of each node is appended to the proof.
    // A final unpaired element in any level is paired with itself.
    // Every proof thus has length equal to the height of the tree minus 1.
    function buildProof(bytes32[][] memory tree, uint256 index) internal pure returns (bytes32[] memory) {
        require(index < tree[tree.length - 1].length, "Index out of bounds");

        bytes32[] memory proof = new bytes32[](tree.length - 1);
        uint256 proofIndex = 0;

        for (uint256 i = tree.length - 1; i > 0; i--) {
            uint256 levelSize = tree[i].length;
            uint256 pairIndex = index ^ 1; // XOR with 1 to get the pair index

            if (pairIndex < levelSize) {
                proof[proofIndex] = tree[i][pairIndex];
            } else {
                // Pair final odd node with itself
                proof[proofIndex] = tree[i][index];
            }
            proofIndex++;
            index /= 2; // Move to the parent node
        }
        return proof;
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
        bytes32 result = Hashes.orderedHash(a, b);
        assertEq(result, expected, "Hashes.commutativeHash should return the expected hash");
    }

    // Implements commutative SHA256 hash of pairs via the standard sha256(abi.encode(a, b)).
    function expectedHash(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        bytes memory payload = abi.encodePacked(a, b);
        return sha256(payload);
    }

}