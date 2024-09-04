// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

contract PDPService {
    // Types 
    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329836995 
    struct Cid {
        bytes data;
    }

    // State fields

    /*
    A proof set is the metadata required for tracking data for proof of possession.
    It maintains a list of CIDs of data to be proven and metadata needed to 
    add and remove data to the set and prove possession efficiently.

    ** logical structure of the proof set**
    /* 
    struct ProofSet {
        Cid[] roots; 
        uint256[] sizes;
        uint256[] sumTree;
        uint256 size;
        address owner;
        nextRootID uint64;
    }
    ** PDP service contract tracks many possible proof sets **
    []ProofSet proofsets

    To implement this logical structure in the solidity data model we have
    two arrays tracking the singleton fields and three two dimensional arrays
    tracking the growing data of the proof set.  The first index is the proof set id
    and the second index is the index of the data in the array.

    Invariant: rootCids.length == rootSizes.length == sumTreeSizes.length
    */

    // Network epoch delay between last proof of possession and next 
    // randomness sampling for challenge generation
    uint256 challengeFinality;
   
    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329838769
    uint64 nextProofSetId;
    mapping(uint256 => mapping(uint256 => Cid)) rootCids; 
    mapping(uint256 => mapping(uint256 => uint256)) rootSizes;
    mapping(uint256 => mapping(uint256 => uint256)) sumTreeSizes;
    mapping(uint256 => uint256) nextRootId;
    mapping(uint256 => uint256) proofSetSize;
    // ownership of proof set is initialized upon creation to create message sender 
    // proofset owner has exclusive permission to add and remove roots and delete the proof set
    mapping(uint256 => address) proofSetOwner;

    // Methods
    constructor(uint256 _challengeFinality) {
        challengeFinality = _challengeFinality;
    }

    // Returns the current challenge finality value
    function getChallengeFinality() public view returns (uint256) {
        return challengeFinality;
    }

    // Returns the next proof set ID
    function getNextProofSetId() public view returns (uint64) {
        return nextProofSetId;
    }

    // Returns the size of a proof set
    function getProofSetSize(uint256 setId) public view returns (uint256) {
        require(setId < nextProofSetId, "Proof set ID out of bounds");
        return proofSetSize[setId];
    }

    // Returns the next root ID for a proof set
    function getNextRootId(uint256 setId) public view returns (uint256) {
        require(setId < nextProofSetId, "Proof set ID out of bounds");
        return nextRootId[setId];
    }

    // Returns the owner of a proof set
    function getProofSetOwner(uint256 setId) public view returns (address) {
        require(setId < nextProofSetId, "Proof set ID out of bounds");
        return proofSetOwner[setId];
    }

    // Returns the root CID for a given proof set and root ID
    function getRootCid(uint256 setId, uint256 rootId) public view returns (Cid memory) {
        require(setId < nextProofSetId, "Proof set ID out of bounds");
        require(rootId < nextRootId[setId], "Root ID out of bounds");
        return rootCids[setId][rootId];
    }

    // Returns the root size for a given proof set and root ID
    function getRootSize(uint256 setId, uint256 rootId) public view returns (uint256) {
        require(setId < nextProofSetId, "Proof set ID out of bounds");
        require(rootId < nextRootId[setId], "Root ID out of bounds");
        return rootSizes[setId][rootId];
    }

    // Returns the sum tree size for a given proof set and root ID
    function getSumTreeSize(uint256 setId, uint256 rootId) public view returns (uint256) {
        require(setId < nextProofSetId, "Proof set ID out of bounds");
        require(rootId < nextRootId[setId], "Root ID out of bounds");
        return sumTreeSizes[setId][rootId];
    }

    // A proof set is created empty, with no roots. Creation yields a proof set ID 
    // for referring to the proof set later.
    // Sender of create message is proof set owner.
    function createProofSet() public returns (uint256) {
        uint256 setId = nextProofSetId++;
        proofSetSize[setId] = 0;
        proofSetOwner[setId] = msg.sender;
        return setId;
    }

    // Removes a proof set. Must be called by the contract owner.   
    function deleteProofSet(uint256 setId) public {
        if (setId >= nextProofSetId) {
            revert("proof set id out of bounds");
        }
        require(proofSetOwner[setId] == msg.sender, "Only the owner can delete proof sets");

        proofSetSize[setId] = 0;
        proofSetOwner[setId] = address(0);
    }

    // Appends a new root to the collection managed by a proof set.
    // Must be called by the contract owner.
    function addRoot(uint256 setId, Cid calldata root, uint256 size) public returns (uint256) {
        require(proofSetOwner[setId] == msg.sender, "Only the owner can add roots");
        // TODO: implement me
        return 0;
    }

    // Removes a root from a proof set. Must be called by the contract owner.
    function removeRoot(uint256 setId, uint256 rootId) public {
        require(proofSetOwner[setId] == msg.sender, "Only the owner can remove roots");
        // TODO: implement me
    }

    // Verifies and records that the provider proved possession of the 
    // proof set Merkle roots at some epoch. The challenge seed is determined 
    // by the previous proof of possession
    // TODO: proof will probably be a new type not just bytes
    function provePossession(uint256 setId, bytes calldata proof) public {
        // TODO: implement me
        // TODO: ownership check for proof validation? I don't think its necessary but maybe useful? 
    }
}
