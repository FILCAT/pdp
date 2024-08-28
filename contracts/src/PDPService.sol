// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

contract PDPService is Ownable {
    // Types 

    // TODO: there is more to think about here.
    // existing libraries (https://github.com/filecoin-project/filecoin-solidity/blob/master/contracts/v0.8/types/CommonTypes.sol#L91)
    // don't give us any significant functionality so it makes sense to redeclare.
    // There will be performance benefits both for storage and memory ops to using bytes32 but we should wait 
    // on measurment before making that decision.  We could potentially use bytes32 hash and bytes8 for the prefix.
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
        bool deleted;
    }
    ** PDP service contract tracks many possible proof sets **
    []ProofSet proofsets

    To implement this logical structure in the solidity data model we have
    two arrays tracking the singleton fields and three two dimensional arrays
    tracking the growing data of the proof set.  The first index is the proof set id
    and the second index is the index of the data in the array.

    Invariant: rootCids.length == rootSizes.length == sumTreeSizes.length == proofSetSize.length
    */

    uint256 public challengeFinality;
    // TODO: a single mapping with a pair key i.e. (uint256, uint256 )
    // might be more efficient as it will half the hashing needed for access and set
    mapping(uint256 => Cid[]) rootCids; 
    mapping(uint256 => uint256[]) rootSizes;
    mapping(uint256 => uint256[]) sumTreeSizes;
    bool[] public proofSetDeleted;
    uint256[] public proofSetSize;

    // Methods
    constructor(uint256 _challengeFinality) Ownable(msg.sender) {
        challengeFinality = _challengeFinality;
    }

    // A proof set is created empty, with no roots. Creation yields a proof set ID 
    // for referring to the proof set later.
    function createProofSet() public returns (uint256) {
        require(owner() == msg.sender, "Only the owner can create proof sets");
        uint256 setId = proofSetSize.length;
        proofSetSize.push(0);
        proofSetDeleted.push(false);
        rootCids[setId].push();
        rootSizes[setId].push();
        sumTreeSizes[setId].push();

        return setId;
    }

    // Removes a proof set. Must be called by the contract owner.   
    function deleteProofSet(uint256 setId) public {
        if (proofSetDeleted[setId]) {
            revert("Proof set already deleted");
        }
        require(owner() == msg.sender, "Only the owner can delete proof sets");
        require(setId < proofSetSize.length, "Invalid proof set ID");

        proofSetDeleted[setId] = true;
        proofSetSize[setId] = 0;
        delete rootCids[setId];
        delete rootSizes[setId];
        delete sumTreeSizes[setId];
    }

    // Appends a new root to the collection managed by a proof set.
    // Must be called by the contract owner.
    function addRoot(uint256 setId, Cid calldata root, uint256 size) public returns (uint256) {
        // TODO: implement me
        return 0;
    }

    // Removes a root from a proof set. Must be called by the contract owner.
    function removeRoot(uint256 setId, uint256 rootId) public {
        // TODO: implement me
    }

    // Verifies and records that the provider proved possession of the 
    // proof set Merkle roots at some epoch. The challenge seed is determined 
    // by the previous proof of possession
    // TODO: proof will probably be a new type not just bytes
    function provePossession(uint256 setId, bytes calldata proof) public {
        // TODO: implement me
    }

}