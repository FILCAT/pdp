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
        for (uint256 i = 0; i < rootData.length; i++) {
            addOneRoot(setId, i, rootData[i].root, rootData[i].rawSize);
        }
    }

    error IndexedError(uint256 idx, string msg);

    // Appends a new root to the collection managed by a proof set.
    // Must be called by the proof set owner.  
    function addOneRoot(uint256 setId, uint256 callIdx, Cid calldata root, uint256 rawSize) internal returns (uint256) {
        if (proofSetOwner[setId] != msg.sender) {
            revert IndexedError(callIdx, "Only the owner can add roots");
        }
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

    // removeRoot removes a root from a proof set. Must be called by the contract owner.
    function removeRoot(uint256 setId, uint256 rootId) public returns (uint256) {
        require(proofSetOwner[setId] == msg.sender, "Only the owner can remove roots");
        require(proofSetLive(setId), "Proof set not live");
        uint256 delta = rootSizes[setId][rootId];
        sumTreeRemove(setId, rootId, delta);
        delete rootSizes[setId][rootId];
        delete rootCids[setId][rootId];
        proofSetSize[setId] -= delta;
        return delta;
    }

    // findRoot returns the root id for a given chunk index
    // It does this by running a binary search over the logical array
    // To do this efficiently we walk the sumtree 
    function findRootId(uint256 setId, uint256 chunkIndex) public view returns (uint256) { 
        require(chunkIndex < proofSetSize[setId], "Chunk index out of bounds");
        // The top of the sumtree is the largest power of 2 less than the number of roots
        uint256 top = 256 - clz(nextRootId[setId]);
        uint256 searchPtr = (1 << top) - 1;
        uint256 acc = 0;

        //Binary search until we find the index of the sumtree leaf covering the index range
        uint256 candidate;
        for (uint256 h = top; h > 0; h--) {
            // Search has taken us past the end of the sumtree
            // Only option is to go left
            if (searchPtr >= nextRootId[setId]) {
                searchPtr -= 1 << (h - 1);
                continue;
            }

            candidate = acc + sumTreeSizes[setId][searchPtr]; 
            // Go right            
            if (candidate <= chunkIndex) { 
                acc += sumTreeSizes[setId][searchPtr];
                searchPtr += 1 << (h - 1);
            } else {
                // Go left
                searchPtr -= 1 << (h - 1);
            }
        }
        candidate = acc + sumTreeSizes[setId][searchPtr];
        if (candidate <= chunkIndex) {
            // Choose right 
            searchPtr += 1;
        } // else choose left

        return searchPtr;
    }
    // TODO: combine with function merging in merkle proof testing PR
    // Helper function to calculate the number of leading zeros in binary representation
    function clz(uint256 x) internal pure returns (uint256) {
        uint256 n = 256;
        uint256 y;

        y = x >> 128; if (y != 0) { n -= 128; x = y; }
        y = x >> 64;  if (y != 0) { n -= 64;  x = y; }
        y = x >> 32;  if (y != 0) { n -= 32;  x = y; }
        y = x >> 16;  if (y != 0) { n -= 16;  x = y; }
        y = x >> 8;   if (y != 0) { n -= 8;   x = y; }
        y = x >> 4;   if (y != 0) { n -= 4;   x = y; }
        y = x >> 2;   if (y != 0) { n -= 2;   x = y; }
        y = x >> 1;   if (y != 0) return n - 2;
        return n - x;
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

    // Perform sumtree removal
    //
    function sumTreeRemove(uint256 setId, uint256 index, uint256 delta) internal {
        uint256 top = uint256(256 - clz(nextRootId[setId]));
        uint256 h = uint256(heightFromIndex(uint32(index)));

        // Deletion traversal either terminates at 
        // 1) the top of the tree or
        // 2) the highest node right of the removal index
        while (h <= top && index < nextRootId[setId]) {
            sumTreeSizes[setId][index] -= delta;
            index += 1 << h;
            h = heightFromIndex(uint32(index));
        }
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
