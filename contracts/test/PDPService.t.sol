pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPService} from "../src/PDPService.sol";


contract PDPServiceProofSetCreateDeleteTest is Test {
    PDPService pdpService;

    function setUp() public {
        pdpService = new PDPService(2);
    }

    function testCreateProofSet() public {
        uint256 setId = pdpService.createProofSet();
        assertEq(setId, 0, "First proof set ID should be 0");
        assertEq(pdpService.getProofSetLeafCount(setId), 0, "Proof set leaf count should be 0");
        assertEq(pdpService.getProofSetOwner(setId), address(this), "Proof set owner should be the constructor sender");
    }

    function testDeleteProofSet() public {
        uint256 setId = pdpService.createProofSet();
        pdpService.deleteProofSet(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetLeafCount(setId);
    }

    function testOnlyOwnerCanDeleteProofSet() public {
        uint256 setId = pdpService.createProofSet();
        // Create a new address to act as a non-owner
        address nonOwner = address(0x1234);
        // Expect revert when non-owner tries to delete the proof set
        vm.prank(nonOwner);
        vm.expectRevert("Only the owner can delete proof sets");
        pdpService.deleteProofSet(setId);

        // Now verify the owner can delete the proof set
        pdpService.deleteProofSet(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetOwner(setId);
    }

    // TODO: once we have addRoots we should test deletion of a non empty proof set
    function testCannotDeleteNonExistentProofSet() public {
        vm.expectRevert("proof set id out of bounds");
        pdpService.deleteProofSet(0);
    }

    function testMethodsOnDeletedProofSetFails() public {
        uint256 setId = pdpService.createProofSet();
        pdpService.deleteProofSet(setId);
        vm.expectRevert("Only the owner can delete proof sets");
        pdpService.deleteProofSet(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetOwner(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetLeafCount(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getRootCid(setId, 0);
        vm.expectRevert("Proof set not live");
        pdpService.getRootLeafCount(setId, 0);
        vm.expectRevert("Proof set not live");
        pdpService.addRoots(setId, new PDPService.RootData[](0));
    }

    function testGetProofSetID() public {
        pdpService.createProofSet();
        pdpService.createProofSet();
        assertEq(2, pdpService.getNextProofSetId(), "Next proof set ID should be 2");
    }
}

contract SumTreeInternalTestPDPService is PDPService {
    constructor(uint256 _challengeFinality) PDPService(_challengeFinality) {}

    function testHeightFromIndex(uint256 index) public view returns (uint256) {
        return heightFromIndex(index);
    }

    function getSumTreeCounts(uint256 setId, uint256 rootId) public view returns (uint256) {
        return sumTreeCounts[setId][rootId];
    }
}

contract SumTreeHeightTest is Test {
    SumTreeInternalTestPDPService pdpService;

    function setUp() public {
        pdpService = new SumTreeInternalTestPDPService(2);
    }

    function testHeightFromIndex() public {
        // https://oeis.org/A001511
        uint8[105] memory oeisA001511 = [
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 6, 
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 7, 
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 6, 
            1, 2, 1, 3, 1, 2, 1, 4, 1
        ];
        for (uint256 i = 0; i < 105; i++) {
            assertEq(uint256(oeisA001511[i]), pdpService.testHeightFromIndex(i) + 1, "Heights from index 0 to 104 should match OEIS A001511");
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/PDPService.sol";

contract SumTreeAddTest is Test {
    SumTreeInternalTestPDPService pdpService;
    uint256 testSetId;

    function setUp() public {
        pdpService = new SumTreeInternalTestPDPService(100); // Assuming 100 as challengeFinality
        testSetId = pdpService.createProofSet();
    }

    function testMultiAdd() public {
        uint256[] memory counts = new uint256[](8);
        counts[0] = 1;
        counts[1] = 2;
        counts[2] = 3;
        counts[3] = 5;
        counts[4] = 8;
        counts[5] = 13;
        counts[6] = 21;
        counts[7] = 34;

        PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](8);

        for (uint256 i = 0; i < counts.length; i++) {
            PDPService.Cid memory testCid = PDPService.Cid(abi.encodePacked("test", i));
            rootDataArray[i] = PDPService.RootData(testCid, counts[i] * pdpService.LEAF_SIZE());
        }
        pdpService.addRoots(testSetId, rootDataArray);
        assertEq(pdpService.getProofSetLeafCount(testSetId), 87, "Incorrect final proof set leaf count");
        assertEq(pdpService.getNextRootId(testSetId), 8, "Incorrect next root ID");
        assertEq(pdpService.getSumTreeCounts(testSetId, 7), 87, "Incorrect sum tree count");
        assertEq(pdpService.getRootLeafCount(testSetId, 7), 34, "Incorrect root leaf count");
        PDPService.Cid memory expectedCid = PDPService.Cid(abi.encodePacked("test", uint256(3)));
        PDPService.Cid memory actualCid = pdpService.getRootCid(testSetId, 3);
        assertEq(actualCid.data, expectedCid.data, "Incorrect root CID");
    }

    function testSumTree() public {
        uint256[] memory counts = new uint256[](8);
        counts[0] = 200;
        counts[1] = 100;
        counts[2] = 1; // Remove
        counts[3] = 30;
        counts[4] = 50;
        counts[5] = 1; // Remove
        counts[6] = 400;
        counts[7] = 40;

        // Correct sum tree values assuming that rootIdsToRemove are deleted
        uint256[] memory expectedSumTreeCounts = new uint256[](8);
        expectedSumTreeCounts[0] = 200;
        expectedSumTreeCounts[1] = 300;
        expectedSumTreeCounts[2] = 0;
        expectedSumTreeCounts[3] = 330;
        expectedSumTreeCounts[4] = 50;
        expectedSumTreeCounts[5] = 50;
        expectedSumTreeCounts[6] = 400;
        expectedSumTreeCounts[7] = 820;

        uint256[] memory rootIdsToRemove = new uint256[](2);
        rootIdsToRemove[0] = 2;
        rootIdsToRemove[1] = 5;

        // Add all
        for (uint256 i = 0; i < counts.length; i++) {
            PDPService.Cid memory testCid = PDPService.Cid(abi.encodePacked("test", i));
            PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
            rootDataArray[0] = PDPService.RootData(testCid, count[i] * pdpService.LEAF_SIZE());
            pdpService.addRoot(testSetId, rootDataArray);
            // Assert the root was added correctly
            assertEq(pdpService.getRootCid(testSetId, i).data, testCid.data, "Root not added correctly");
        }

        // Delete some
        // Remove roots in batch
        pdpService.removeRoots(testSetId, rootIdsToRemove);
        for (uint256 i = 0; i < rootIdsToRemove.length; i++) {
            bytes memory zeroBytes;
            assertEq(pdpService.getRootCid(testSetId, rootIdsToRemove[i]).data, zeroBytes);
            assertEq(pdpService.getRootSize(testSetId, rootIdsToRemove[i]), 0, "Root size should be 0");
        }

        // Assert that the sum tree count is correct
        for (uint256 i = 0; i < sizes.length; i++) {
            assertEq(pdpService.getSumTreeCount(testSetId, i), expectedSumTreeCounts[i], "Incorrect sum tree size");
        }

        // Assert final proof set leaf count
        assertEq(pdpService.getProofSetLeafCount(testSetId), 820, "Incorrect final proof set leaf count");
    }

    function testBatchedRemoveRootsOnlyOwner() public {
        uint256 setId = pdpService.createProofSet();
        PDPService.Cid memory testCid = PDPService.Cid(abi.encodePacked("test"));
        PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
        rootDataArray[0] = PDPService.RootData(testCid, 100 * pdpService.CHUNK_SIZE());
        pdpService.addRoot(setId, rootDataArray);

        address nonOwner = address(0x1234);
        uint256[] memory rootIdsToRemove = new uint256[](1);
        rootIdsToRemove[0] = 0;

        vm.prank(nonOwner);
        vm.expectRevert("Only the owner can remove roots");
        pdpService.removeRoots(setId, rootIdsToRemove);
    }

    function testFindRootId() public {
        // Set up the same array as in testSumTreeAdd
        uint256[] memory sizes = new uint256[](8);
        sizes[0] = 200;
        sizes[1] = 100;
        sizes[2] = 0;
        sizes[3] = 30;
        sizes[4] = 50;
        sizes[5] = 0;
        sizes[6] = 400;
        sizes[7] = 40;

        // Add roots to the proof set
        for (uint256 i = 0; i < sizes.length; i++) {
            PDPService.Cid memory testCid = PDPService.Cid(abi.encodePacked("test", i));
            PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
            rootDataArray[0] = PDPService.RootData(testCid, sizes[i] * pdpService.LEAF_SIZE());
            pdpService.addRoots(testSetId, rootDataArray);
        }

        // Test findRootId for various positions
        assertFindRootAndOffset(testSetId, 0, 0, 0);
        assertFindRootAndOffset(testSetId, 199, 0, 199);
        assertFindRootAndOffset(testSetId, 200, 1, 0);
        assertFindRootAndOffset(testSetId, 299, 1, 99);
        assertFindRootAndOffset(testSetId, 300, 3, 0);
        assertFindRootAndOffset(testSetId, 329, 3, 29);
        assertFindRootAndOffset(testSetId, 330, 4, 0);
        assertFindRootAndOffset(testSetId, 379, 4, 49);
        assertFindRootAndOffset(testSetId, 380, 6, 0);
        assertFindRootAndOffset(testSetId, 779, 6, 399);
        assertFindRootAndOffset(testSetId, 780, 7, 0);
        assertFindRootAndOffset(testSetId, 819, 7, 39);

        // Test edge cases
        vm.expectRevert("Leaf index out of bounds");
        pdpService.findRootId(testSetId, 820);

        vm.expectRevert("Leaf index out of bounds");
        pdpService.findRootId(testSetId, 1000);
    }

    error TestingFindError(uint256 expected, uint256 actual, string msg);

    function assertFindRootAndOffset(uint256 setId, uint256 searchIndex, uint256 expectRootId, uint256 expectOffset) internal view {
        (uint256 rootId, uint256 offset) = pdpService.findRootId(setId, searchIndex);
        if (rootId != expectRootId) {
            revert TestingFindError(expectRootId, rootId, "unexpected root");
        }
        if (offset != expectOffset) {
            revert TestingFindError(expectOffset, offset, "unexpected offset");
        }
    }

    function testFindRootIdTraverseOffTheEdgeAndBack() public {
        uint256[] memory sizes = new uint256[](5);
        sizes[0] = 0;
        sizes[1] = 0;
        sizes[2] = 0;
        sizes[3] = 1;
        sizes[4] = 1;


        for (uint256 i = 0; i < sizes.length; i++) {
            PDPService.Cid memory testCid = PDPService.Cid(abi.encodePacked("test", i));
            PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
            rootDataArray[0] = PDPService.RootData(testCid, sizes[i] * pdpService.LEAF_SIZE());
            pdpService.addRoots(testSetId, rootDataArray);
        }

        assertFindRootAndOffset(testSetId, 0, 3, 0);
        assertFindRootAndOffset(testSetId, 1, 4, 0);
    }
}