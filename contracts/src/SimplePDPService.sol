// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PDPVerifier, PDPListener} from "./PDPVerifier.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";



// PDPRecordKeeper tracks PDP operations.  It is used as a base contract for PDPListeners
// in order to give users the capability to consume events async.
contract PDPRecordKeeper {
    enum OperationType {
        NONE,
        CREATE,
        DELETE,
        ADD,
        REMOVE_SCHEDULED,
        PROVE_POSSESSION,
        NEXT_PROVING_PERIOD
    }    

    // Struct to store event details
    struct EventRecord {
        uint64 epoch;
        uint256 proofSetId;
        OperationType operationType;
        bytes extraData;
    }

    // Eth event emitted when a new record is added
    event RecordAdded(uint256 indexed proofSetId, uint64 epoch, OperationType operationType);

    // Mapping to store events for each proof set
    mapping(uint256 => EventRecord[]) public proofSetEvents;

    function receiveProofSetEvent(uint256 proofSetId, OperationType operationType, bytes memory extraData ) internal {
        uint64 epoch = uint64(block.number);
        EventRecord memory newRecord = EventRecord({
            epoch: epoch,
            proofSetId: proofSetId,
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

// SimplePDPServiceApplication is a default implementation of a PDP Application.
// It maintains a record of all events that have occurred in the PDP service,
// and provides a way to query these events.
// This contract only supports one PDP service caller, set in the constructor.
contract SimplePDPService is PDPListener, PDPRecordKeeper, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // The address of the PDP service contract that is allowed to call this contract
    address public pdpServiceAddress;

     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
     _disableInitializers();
    }

    function initialize(address _pdpServiceAddress) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
require(_pdpServiceAddress != address(0), "PDP service address cannot be zero");
        pdpServiceAddress = _pdpServiceAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Modifier to ensure only the PDP verifier contract can call certain functions
    modifier onlyPDPVerifier() {
        require(msg.sender == pdpServiceAddress, "Caller is not the PDP verifier");
        _;
    }

    // Listener interface methods
    function proofSetCreated(uint256 proofSetId, address creator) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.CREATE, abi.encode(creator));
    }

    function proofSetDeleted(uint256 proofSetId, uint256 deletedLeafCount) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.DELETE, abi.encode(deletedLeafCount));
    }

    function rootsAdded(uint256 proofSetId, uint256 firstAdded, PDPVerifier.RootData[] memory rootData) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.ADD, abi.encode(firstAdded, rootData));
    }

    function rootsScheduledRemove(uint256 proofSetId, uint256[] memory rootIds) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.REMOVE_SCHEDULED, abi.encode(rootIds));
    }

    function posessionProven(uint256 proofSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.PROVE_POSSESSION, abi.encode(challengedLeafCount, seed, challengeCount));
    }

    function nextProvingPeriod(uint256 proofSetId, uint256 leafCount) external onlyPDPVerifier {
        receiveProofSetEvent(proofSetId, OperationType.NEXT_PROVING_PERIOD, abi.encode(leafCount));
    }
}
