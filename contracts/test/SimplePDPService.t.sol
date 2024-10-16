// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPListener} from "../src/PDPVerifier.sol";
import {SimplePDPService} from "../src/SimplePDPService.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";


contract SimplePDPServiceTest is Test {
    SimplePDPService public pdpService;
    address public pdpServiceAddress;

    function setUp() public {
        pdpServiceAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpServiceAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
    }

    function testInitialState() public view {
        assertEq(pdpService.pdpServiceAddress(), pdpServiceAddress, "PDP verifier address should be set correctly");
    }

    function testAddRecord() public {
        uint256 proofSetId = 1;
        uint64 epoch = 100;
        PDPListener.OperationType operationType = PDPListener.OperationType.CREATE;
        bytes memory extraData = abi.encode("test data");

        pdpService.receiveProofSetEvent(proofSetId, epoch, operationType, extraData);

        assertEq(pdpService.getEventCount(proofSetId), 1, "Event count should be 1 after adding a record");

        SimplePDPService.EventRecord memory eventRecord = pdpService.getEvent(proofSetId, 0);

        assertEq(eventRecord.epoch, epoch, "Recorded epoch should match");
        assertEq(uint(eventRecord.operationType), uint(operationType), "Recorded operation type should match");
        assertEq(eventRecord.extraData, extraData, "Recorded extra data should match");
    }

    function testListEvents() public {
        uint256 proofSetId = 1;
        uint64 epoch1 = 100;
        uint64 epoch2 = 200;
        PDPListener.OperationType operationType1 = PDPListener.OperationType.CREATE;
        PDPListener.OperationType operationType2 = PDPListener.OperationType.ADD;
        bytes memory extraData1 = abi.encode("test data 1");
        bytes memory extraData2 = abi.encode("test data 2");

        pdpService.receiveProofSetEvent(proofSetId, epoch1, operationType1, extraData1);
        pdpService.receiveProofSetEvent(proofSetId, epoch2, operationType2, extraData2);

        SimplePDPService.EventRecord[] memory events = pdpService.listEvents(proofSetId);

        assertEq(events.length, 2, "Should have 2 events");
        assertEq(events[0].epoch, epoch1, "First event epoch should match");
        assertEq(uint(events[0].operationType), uint(operationType1), "First event operation type should match");
        assertEq(events[0].extraData, extraData1, "First event extra data should match");
        assertEq(events[1].epoch, epoch2, "Second event epoch should match");
        assertEq(uint(events[1].operationType), uint(operationType2), "Second event operation type should match");
        assertEq(events[1].extraData, extraData2, "Second event extra data should match");
    }

    function testOnlyPDPVerifierCanAddRecord() public {
        uint256 proofSetId = 1;
        uint64 epoch = 100;
        PDPListener.OperationType operationType = PDPListener.OperationType.CREATE;
        bytes memory extraData = abi.encode("test data");

        vm.prank(address(0xdead));
        vm.expectRevert("Caller is not the PDP verifier");
        pdpService.receiveProofSetEvent(proofSetId, epoch, operationType, extraData);
    }

    function testGetEventOutOfBounds() public {
        uint256 proofSetId = 1;
        vm.expectRevert("Event index out of bounds");
        pdpService.getEvent(proofSetId, 0);
    }
}