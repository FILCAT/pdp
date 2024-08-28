// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPService} from "../src/PDPService.sol";

contract PDPServiceOwnershipTest is Test {
   PDPService pdpService;

    function setUp() public {
        pdpService = new PDPService(2);
    }

    function testOwnerIsConstructorSender() public view {
        address expectedOwner = address(this);
        address actualOwner = pdpService.owner();
        assertEq(expectedOwner, actualOwner, "Owner should be the constructor sender");
    } 
}

contract PDPServiceProofSetCreateDeleteTest is Test {
    PDPService pdpService;

    function setUp() public {
        pdpService = new PDPService(2);
    }

    function testCreateProofSet() public {
        uint256 setId = pdpService.createProofSet();
        assertEq(setId, 0, "First proof set ID should be 0");
        assertFalse(pdpService.proofSetDeleted(setId), "Proof set should not be marked as deleted");
        assertEq(pdpService.proofSetSize(setId), 0, "Proof set size should be 0");
    }

    function testDeleteProofSet() public {
        uint256 setId = pdpService.createProofSet();
        pdpService.deleteProofSet(setId);
        assertTrue(pdpService.proofSetDeleted(setId), "Proof set should be marked as deleted");
        assertEq(pdpService.proofSetSize(setId), 0, "Proof set size should be 0 after deletion");
    }

    // TODO: once we have addRoot we should test deletion of a non empty proof set

    function testCannotDeleteNonExistentProofSet() public {
        vm.expectRevert("proof set id out of bounds");
        pdpService.deleteProofSet(0);
    }

    function testCannotDeleteAlreadyDeletedProofSet() public {
        uint256 setId = pdpService.createProofSet();
        pdpService.deleteProofSet(setId);
        vm.expectRevert("Proof set already deleted");
        pdpService.deleteProofSet(setId);
    }
}