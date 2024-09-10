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

    function testHeightFromIndex(uint32 index) public view returns (uint8) {
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
        for (uint32 i = 0; i < 105; i++) {
            assertEq(oeisA001511[i], pdpService.testHeightFromIndex(i) + 1, "Heights from index 0 to 104 should match OEIS A001511");
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

    function testSumTreeAdd() public {
        uint256[] memory counts = new uint256[](8);
        counts[0] = 200;
        counts[1] = 100;
        counts[2] = 0;
        counts[3] = 30;
        counts[4] = 50;
        counts[5] = 0;
        counts[6] = 400;
        counts[7] = 40;

        uint256[] memory expectedSumTreeCounts = new uint256[](8);
        expectedSumTreeCounts[0] = 200;
        expectedSumTreeCounts[1] = 300;
        expectedSumTreeCounts[2] = 0;
        expectedSumTreeCounts[3] = 330;
        expectedSumTreeCounts[4] = 50;
        expectedSumTreeCounts[5] = 50;
        expectedSumTreeCounts[6] = 400;
        expectedSumTreeCounts[7] = 820;

        for (uint256 i = 0; i < counts.length; i++) {
            PDPService.Cid memory testCid = PDPService.Cid(abi.encodePacked("test", i));
            PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
            rootDataArray[0] = PDPService.RootData(testCid, counts[i] * pdpService.LEAF_SIZE());
            pdpService.addRoots(testSetId, rootDataArray);

            // Assert that the root was added
            assertEq(pdpService.getRootCid(testSetId, i).data, testCid.data, "Root not added correctly");

            // Assert that the sum tree count is correct
            assertEq(pdpService.getSumTreeCounts(testSetId, i), expectedSumTreeCounts[i], "Incorrect sum tree count");
        }

        // Assert final proof set leaf count
        assertEq(pdpService.getProofSetLeafCount(testSetId), 820, "Incorrect final proof set leaf count");
    }
}