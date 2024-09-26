// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// PDPRecordKeeper is a default implementation of a record keeper for the PDP service.
// It maintains a record of all events that have occurred in the PDP service,
// and provides a way to query these events.
// This contract only supports one PDP service caller, set in the constructor.
contract PDPRecordKeeper {
    // The address of the PDP service contract that is allowed to call this contract
    address public immutable pdpServiceAddress;

    // Enum to represent different types of operations
    enum OperationType {
        CREATE,
        ADD,
        REMOVE,
        PROVE_POSSESSION,
        DELETE
    }

    // Struct to store event details
    struct EventRecord {
        uint64 epoch;
        OperationType operationType;
        bytes extraData;
    }

    // Mapping to store events for each proof set
    mapping(uint256 => EventRecord[]) public proofSetEvents;

    // Eth event emitted when a new record is added
    event RecordAdded(uint256 indexed proofSetId, uint64 epoch, OperationType operationType);

    constructor(address _pdpServiceAddress) {
        require(_pdpServiceAddress != address(0), "PDP service address cannot be zero");
        pdpServiceAddress = _pdpServiceAddress;
    }

    // Modifier to ensure only the PDP service contract can call certain functions
    modifier onlyPDPService() {
        require(msg.sender == pdpServiceAddress, "Caller is not the PDP service");
        _;
    }

    // Function to add a new event record
    function addRecord(
        uint256 proofSetId,
        uint64 epoch,
        OperationType operationType,
        bytes calldata extraData
    ) external onlyPDPService {
        EventRecord memory newRecord = EventRecord({
            epoch: epoch,
            operationType: operationType,
            extraData: extraData
        });
        proofSetEvents[proofSetId].push(newRecord);
        emit RecordAdded(proofSetId, epoch, operationType);
    }

    // Function to get the number of events for a proof set
    function getEventCount(uint256 proofSetId) external view returns (uint256) {
        return proofSetEvents[proofSetId].length;
    }

    // Function to get a specific event for a proof set
    function getEvent(uint256 proofSetId, uint256 eventIndex) 
        external 
        view 
        returns (EventRecord memory) 
    {
        require(eventIndex < proofSetEvents[proofSetId].length, "Event index out of bounds");
        return proofSetEvents[proofSetId][eventIndex];
    }

    // Function to get all events for a proof set
    function listEvents(uint256 proofSetId) external view returns (EventRecord[] memory) {
        return proofSetEvents[proofSetId];
    }
}