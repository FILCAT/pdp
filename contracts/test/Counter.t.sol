// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPService} from "../src/PDPService.sol";

contract PDPServiceOwnershipTest is Test {
   PDPService pdpService;

    function setUp() public {
        pdpService = new PDPService();
    }

    function testOwnerIsConstructorSender() public {
        address expectedOwner = address(this);
        address actualOwner = pdpService.owner();
        assertEq(expectedOwner, actualOwner, "Owner should be the constructor sender");
    } 
}
