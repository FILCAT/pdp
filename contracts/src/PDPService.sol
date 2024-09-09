// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


contract PDPService {
    // Constants
    uint256 public constant CHUNK_SIZE = 256;
    int32 constant MASK16 = 0x0000FFFF;
    int32 constant MASK8 = 0x00FF00FF;
    int32 constant MASK4 = 0x0F0F0F0F;
    int32 constant MASK2 = 0x33333333;
    int32 constant MASK1 = 0x55555555;

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

    // Returns false if the proof set is 1) not yet created 2) deleted
    function proofSetLive(uint256 setId) public view returns (bool) {
        return setId < nextProofSetId && proofSetOwner[setId] != address(0);
    }

    // Returns false if the proof set is not live or if the root id is 1) not yet created 2) deleted
    function rootLive(uint256 setId, uint256 rootId) public view returns (bool) {
        return proofSetLive(setId) && rootId < nextRootId[setId] && rootSizes[setId][rootId] > 0;
    }

    // Returns the size of a proof set
    function getProofSetSize(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return proofSetSize[setId];
    }

    // Returns the next root ID for a proof set
    function getNextRootId(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return nextRootId[setId];
    }

    // Returns the owner of a proof set
    function getProofSetOwner(uint256 setId) public view returns (address) {
        require(proofSetLive(setId), "Proof set not live");
        return proofSetOwner[setId];
    }

    // Returns the root CID for a given proof set and root ID
    function getRootCid(uint256 setId, uint256 rootId) public view returns (Cid memory) {
        require(proofSetLive(setId), "Proof set not live");
        return rootCids[setId][rootId];
    }

    // Returns the root size for a given proof set and root ID
    function getRootSize(uint256 setId, uint256 rootId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return rootSizes[setId][rootId];
    }

    // Returns the sum tree size for a given proof set and root ID
    function getSumTreeSize(uint256 setId, uint256 rootId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
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

    // Struct for tracking root data
    struct RootData {
        Cid root;
        uint256 rawSize;
    }

    function addRoot(uint256 setId, RootData[] calldata rootData) public {
        require(proofSetLive(setId), "Proof set not live");
        require(proofSetOwner[setId] == msg.sender, "Only the owner can add roots");

        for (uint256 i = 0; i < rootData.length; i++) {
            addOneRoot(setId, i, rootData[i].root, rootData[i].rawSize);
        }
    }

    error IndexedError(uint256 idx, string msg);

    // Appends a new root to the collection managed by a proof set.
    // Must be called by the proof set owner.  
    function addOneRoot(uint256 setId, uint256 callIdx, Cid calldata root, uint256 rawSize) internal returns (uint256) {
        if (rawSize % CHUNK_SIZE != 0) {
            revert IndexedError(callIdx, "Size must be a multiple of CHUNK_SIZE");
        }

        uint256 size = rawSize / CHUNK_SIZE;
        sumTreeAdd(setId, size);
        uint256 rootId = nextRootId[setId]++;
        rootCids[setId][rootId] = root;
        rootSizes[setId][rootId] = size;
        proofSetSize[setId] += size;
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

    // Perform sumtree addition 
    // 
    function sumTreeAdd(uint256 setId, uint256 size) internal {
        uint32 index = uint32(nextRootId[setId]);
        uint32 h = heightFromIndex(index);
        
        uint256 sum = size;
        // Sum BaseArray[j - 2^i] for i in [0, h)
        for (uint32 i = 0; i < h; i++) {
            uint32 j = index - uint32(1 << i);
            sum += sumTreeSizes[setId][j];
        }
        sumTreeSizes[setId][nextRootId[setId]] = sum;        
    }

    // Return height of sumtree node at given index
    // Calculated by taking the trailing zeros of 1 plus the index
    function heightFromIndex(uint32 index) internal pure returns (uint8) {
        uint8 h = 31; // Operating on index + 1 means we never have index == 0 so there's always a leading 1
        int32 v = -int32(index + 1);
        v = v & int32(index+1);
        if (v & MASK16 != 0) {
            h -= 16;
        }
        if (v & MASK8 != 0) {
            h -= 8;
        }
        if (v & MASK4 != 0) {
            h -= 4;
        }
        if (v & MASK2 != 0) {
            h -= 2;
        }
        if (v & MASK1 != 0) {
            h -= 1;
        }

        return h;
    }

}
