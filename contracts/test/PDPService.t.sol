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
        assertEq(pdpService.getProofSetSize(setId), 0, "Proof set size should be 0");
        assertEq(pdpService.getProofSetOwner(setId), address(this), "Proof set owner should be the constructor sender");
    }

    function testDeleteProofSet() public {
        uint256 setId = pdpService.createProofSet();
        pdpService.deleteProofSet(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetSize(setId);
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

    // TODO: once we have addRoot we should test deletion of a non empty proof set
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
        pdpService.getProofSetSize(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getRootCid(setId, 0);
        vm.expectRevert("Proof set not live");
        pdpService.getRootSize(setId, 0);
        vm.expectRevert("Proof set not live");
        pdpService.getSumTreeSize(setId, 0);
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
}

contract SumTreeHeightTest is Test {
    SumTreeInternalTestPDPService pdpService;

    function setUp() public {
        pdpService = new SumTreeInternalTestPDPService(2);
    }

    function testHeightFromIndex() public {
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
    PDPService pdpService;
    uint256 testSetId;

    function setUp() public {
        pdpService = new PDPService(100); // Assuming 100 as challengeFinality
        testSetId = pdpService.createProofSet();
    }

    function testSumTreeAdd() public {
        uint256[] memory sizes = new uint256[](8);
        sizes[0] = 200;
        sizes[1] = 100;
        sizes[2] = 0;
        sizes[3] = 30;
        sizes[4] = 50;
        sizes[5] = 0;
        sizes[6] = 400;
        sizes[7] = 40;

        uint256[] memory expectedSumTreeSizes = new uint256[](8);
        expectedSumTreeSizes[0] = 200;
        expectedSumTreeSizes[1] = 300;
        expectedSumTreeSizes[2] = 0;
        expectedSumTreeSizes[3] = 330;
        expectedSumTreeSizes[4] = 50;
        expectedSumTreeSizes[5] = 50;
        expectedSumTreeSizes[6] = 400;
        expectedSumTreeSizes[7] = 820;

        for (uint256 i = 0; i < sizes.length; i++) {
            PDPService.Cid memory testCid = PDPService.Cid(abi.encodePacked("test", i));
            PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
            rootDataArray[0] = PDPService.RootData(testCid, sizes[i] * pdpService.CHUNK_SIZE());
            pdpService.addRoot(testSetId, rootDataArray);

            // Assert that the root was added
            assertEq(pdpService.getRootCid(testSetId, i).data, testCid.data, "Root not added correctly");

            // Assert that the sum tree size is correct
            assertEq(pdpService.getSumTreeSize(testSetId, i), expectedSumTreeSizes[i], "Incorrect sum tree size");
        }

        // Assert final proof set size
        assertEq(pdpService.getProofSetSize(testSetId), 820, "Incorrect final proof set size");
    }
}