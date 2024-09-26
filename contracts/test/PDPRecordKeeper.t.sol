// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPRecordKeeper} from "../src/PDPRecordKeeper.sol";

contract PDPRecordKeeperTest is Test {
    PDPRecordKeeper public recordKeeper;
    address public pdpServiceAddress;

    function setUp() public {
        pdpServiceAddress = address(this);
        recordKeeper = new PDPRecordKeeper(pdpServiceAddress);
    }

    function testInitialState() public view {
        assertEq(recordKeeper.pdpServiceAddress(), pdpServiceAddress, "PDP service address should be set correctly");
    }

    function testAddRecord() public {
        uint256 proofSetId = 1;
        uint64 epoch = 100;
        PDPRecordKeeper.OperationType operationType = PDPRecordKeeper.OperationType.CREATE;
        bytes memory extraData = abi.encode("test data");

        recordKeeper.addRecord(proofSetId, epoch, operationType, extraData);

        assertEq(recordKeeper.getEventCount(proofSetId), 1, "Event count should be 1 after adding a record");

        PDPRecordKeeper.EventRecord memory eventRecord = recordKeeper.getEvent(proofSetId, 0);

        assertEq(eventRecord.epoch, epoch, "Recorded epoch should match");
        assertEq(uint(eventRecord.operationType), uint(operationType), "Recorded operation type should match");
        assertEq(eventRecord.extraData, extraData, "Recorded extra data should match");
    }

    function testListEvents() public {
        uint256 proofSetId = 1;
        uint64 epoch1 = 100;
        uint64 epoch2 = 200;
        PDPRecordKeeper.OperationType operationType1 = PDPRecordKeeper.OperationType.CREATE;
        PDPRecordKeeper.OperationType operationType2 = PDPRecordKeeper.OperationType.ADD;
        bytes memory extraData1 = abi.encode("test data 1");
        bytes memory extraData2 = abi.encode("test data 2");

        recordKeeper.addRecord(proofSetId, epoch1, operationType1, extraData1);
        recordKeeper.addRecord(proofSetId, epoch2, operationType2, extraData2);

        PDPRecordKeeper.EventRecord[] memory events = recordKeeper.listEvents(proofSetId);

        assertEq(events.length, 2, "Should have 2 events");
        assertEq(events[0].epoch, epoch1, "First event epoch should match");
        assertEq(uint(events[0].operationType), uint(operationType1), "First event operation type should match");
        assertEq(events[0].extraData, extraData1, "First event extra data should match");
        assertEq(events[1].epoch, epoch2, "Second event epoch should match");
        assertEq(uint(events[1].operationType), uint(operationType2), "Second event operation type should match");
        assertEq(events[1].extraData, extraData2, "Second event extra data should match");
    }

    function testOnlyPDPServiceCanAddRecord() public {
        uint256 proofSetId = 1;
        uint64 epoch = 100;
        PDPRecordKeeper.OperationType operationType = PDPRecordKeeper.OperationType.CREATE;
        bytes memory extraData = abi.encode("test data");

        vm.prank(address(0xdead));
        vm.expectRevert("Caller is not the PDP service");
        recordKeeper.addRecord(proofSetId, epoch, operationType, extraData);
    }

    function testGetEventOutOfBounds() public {
        uint256 proofSetId = 1;
        vm.expectRevert("Event index out of bounds");
        recordKeeper.getEvent(proofSetId, 0);
    }
}