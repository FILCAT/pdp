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

    // Tests that the merkle root of a tree committing to known data (all zeros) matches the
    // externally-known Filecoin piece commitment for the same data.
    // Note that this is only testing a balanced tree (power-of-two payload).
    function testFilecoinCommPEquivalance() public view {
        // Known value for CommP of a 2KiB zero payload copied from built-in actors code.
        uint8[32] memory zeroCommP2KiB = [
            252, 126, 146, 130, 150, 229, 22, 250, 173, 233, 134, 178, 143, 146, 212, 74, 79, 36, 185,
            53, 72, 82, 35, 55, 106, 121, 144, 39, 188, 24, 248, 51
        ];

        bytes32 expected = loadDigest(zeroCommP2KiB);

        // Build payload of of 2KiB of zeros, packed into bytes32 words
        bytes32[] memory payload = new bytes32[](2048 / 32);

        bytes32[][] memory tree = buildMerkleTree(payload);
        assertEq(tree[0][0], expected);
    }

    // Tests that the zero roots returned by the merkle library match the values computed for them here.
    function testZeroRootsComputed() public view {
        bytes32[] memory expected = buildZeroPaddingStack(51);
        // console.log("Zero roots:");
        // for (uint i = 0; i < zeroRoots.length; i++)  {
        //     console.log(vm.toString(i), vm.toString(zeroRoots[i]));
        // }
        for (uint height = 0; height <= 50; height++) {
            assertEq(MerkleProof.zeroRoot(height), expected[height]);
        }
    }

    // Tests some zero roots against known values for Filecoin sector sizes.
    // The target digets are copied directly from built-in actors code.
    function testZeroRootFilecoinEquivalence() public pure {
        assertEq(MerkleProof.zeroRoot(0), 0);
        // 2 KiB / 32 = 64 leaves = 2^6
        assertEq(MerkleProof.zeroRoot(6), loadDigest([
            252, 126, 146, 130, 150, 229, 22, 250, 173, 233, 134, 178, 143, 146, 212, 74, 79, 36, 185,
            53, 72, 82, 35, 55, 106, 121, 144, 39, 188, 24, 248, 51
        ]));
        // 8 MiB = 256Ki leaves = 2^8 * 2^10
        assertEq(MerkleProof.zeroRoot(18), loadDigest([
            101, 242, 158, 93, 152, 210, 70, 195, 139, 56, 140, 252, 6, 219, 31, 107, 2, 19, 3, 197,
            162, 137, 0, 11, 220, 232, 50, 169, 195, 236, 66, 28
        ]));
        // 512 MiB = 16Mi leaves = 2^4 * 2^20
        assertEq(MerkleProof.zeroRoot(24), loadDigest([
            57, 86, 14, 123, 19, 169, 59, 7, 162, 67, 253, 39, 32, 255, 167, 203, 62, 29, 46, 80, 90,
            179, 98, 158, 121, 244, 99, 19, 81, 44, 218, 6
        ]));
        // 32 GiB = 1Gi leaves = 2^30
        assertEq(MerkleProof.zeroRoot(30), loadDigest([
            7, 126, 95, 222, 53, 197, 10, 147, 3, 165, 80, 9, 227, 73, 138, 78, 190, 223, 243, 156, 66,
            183, 16, 183, 48, 216, 236, 122, 199, 175, 166, 62
        ]));
        // 64 GiB = 2 * 1Gi leaves = 2^1 * 2^30
        assertEq(MerkleProof.zeroRoot(31), loadDigest([
            230, 64, 5, 166, 191, 227, 119, 121, 83, 184, 173, 110, 249, 63, 15, 202, 16, 73, 178, 4,
            22, 84, 242, 164, 17, 247, 112, 39, 153, 206, 206, 2
        ]));
    }

    // Tests that trees with explicit zero leaves produce known values for the root of the all-zero tree.
    function testZeroTreeFilecoinEquivalence() public view {
        for (uint i = 1; i <= 16; i++) {
            bytes32[] memory leaves = new bytes32[](i);
            bytes32[][] memory tree = buildMerkleTree(leaves);
            uint256 height = 256 - BitOps.clz(i - 1);
            assertEq(tree[0][0], MerkleProof.zeroRoot(height));
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
    // An unpaired element is paired with the root of a tree of the same height with zero leaves.
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
                    // Pair final odd node with a zero-tree of same height.
                    tree[i - 1][j] = Hashes.orderedHash(currentLevel[2 * j], MerkleProof.zeroRoot(levels - i));
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
                // Pair final odd node with zero-tree of same height.
                proof[proofIndex] = MerkleProof.zeroRoot(tree.length - 1 - i);
            }
            proofIndex++;
            index /= 2; // Move to the parent node
        }
        return proof;
    }

    // Returns an array of Merkle tree roots committing to all-zero data of increasing tree heights.
    // The first entry is zero.
    // The second entry is a node with two zero leaves.
    // The third entry is a node with four zero leaves, etc.
    function buildZeroPaddingStack(uint256 levels) public view returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](levels);
        for (uint i = 1; i < levels; i++) {
            result[i] = Hashes.orderedHash(result[i-1], result[i-1]);
        }

        return result;
    }

    // Loads a bytes32 hash digest from an array of 32 1-byte values.
    function loadDigest(uint8[32] memory b) public pure returns (bytes32) {
        bytes32 result;
        for (uint i = 0; i < 32; i++) {
            result |= bytes32(uint256(b[i]) << (8 * (31 - i)));
        }
        return result;
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

    // Implements SHA254 hash of pairs via the standard sha256(abi.encode(a, b)).
    function expectedHash(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        bytes memory payload = abi.encodePacked(a, b);
        bytes32 digest = sha256(payload);
        digest = bytes32((uint256(digest) & Hashes.SHA254_MASK));
        return digest;
    }
}
