// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BitOps} from "../src/BitOps.sol";

contract PDPService {
    // Constants
    uint256 public constant LEAF_SIZE = 32;

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
        uint256[] leafCounts;
        uint256[] sumTree;
        uint256 leafCount;
        address owner;
        nextRootID uint64;
    }
    ** PDP service contract tracks many possible proof sets **
    []ProofSet proofsets

    To implement this logical structure in the solidity data model we have
    two arrays tracking the singleton fields and three two dimensional arrays
    tracking the growing data of the proof set.  The first index is the proof set id
    and the second index is the index of the data in the array.

    Invariant: rootCids.length == rootLeafCount.length == sumTreeCounts.length
    */

    // Network epoch delay between last proof of possession and next 
    // randomness sampling for challenge generation
    uint256 challengeFinality;
   
    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329838769
    uint64 nextProofSetId;
    mapping(uint256 => mapping(uint256 => Cid)) rootCids; 
    mapping(uint256 => mapping(uint256 => uint256)) rootLeafCounts;
    mapping(uint256 => mapping(uint256 => uint256)) sumTreeCounts;
    mapping(uint256 => uint256) nextRootId;
    mapping(uint256 => uint256) proofSetLeafCount;
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
        return proofSetLive(setId) && rootId < nextRootId[setId] && rootLeafCounts[setId][rootId] > 0;
    }

    // Returns the leaf count of a proof set
    function getProofSetLeafCount(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return proofSetLeafCount[setId];
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

    // Returns the root leaf count for a given proof set and root ID
    function getRootLeafCount(uint256 setId, uint256 rootId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return rootLeafCounts[setId][rootId];
    }

    // A proof set is created empty, with no roots. Creation yields a proof set ID 
    // for referring to the proof set later.
    // Sender of create message is proof set owner.
    function createProofSet() public returns (uint256) {
        uint256 setId = nextProofSetId++;
        proofSetLeafCount[setId] = 0;
        proofSetOwner[setId] = msg.sender;
        return setId;
    }

    // Removes a proof set. Must be called by the contract owner.   
    function deleteProofSet(uint256 setId) public {
        if (setId >= nextProofSetId) {
            revert("proof set id out of bounds");
        }

        require(proofSetOwner[setId] == msg.sender, "Only the owner can delete proof sets");

        proofSetLeafCount[setId] = 0;
        proofSetOwner[setId] = address(0);
    }

    // Struct for tracking root data
    struct RootData {
        Cid root;
        uint256 rawSize;
    }

    function addRoots(uint256 setId, RootData[] calldata rootData) public returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        require(rootData.length > 0, "Must add at least one root");
        require(proofSetOwner[setId] == msg.sender, "Only the owner can add roots");
        uint256 firstAdded = nextRootId[setId];

        for (uint256 i = 0; i < rootData.length; i++) {
            addOneRoot(setId, i, rootData[i].root, rootData[i].rawSize);
        }
        return firstAdded;
    }

    error IndexedError(uint256 idx, string msg);

    // Appends a new root to the collection managed by a proof set.
    // Must be called by the proof set owner.  
    function addOneRoot(uint256 setId, uint256 callIdx, Cid calldata root, uint256 rawSize) internal returns (uint256) {
        if (rawSize % LEAF_SIZE != 0) {
            revert IndexedError(callIdx, "Size must be a multiple of 256");
        }
        // TODO: add this check after remove operation is implemented and we can easily
        // test 0 sizes without adding them directly.
        // if (rawSize == 0) {
        //     revert IndexedError(callIdx, "Size must be greater than 0");
        // }

        uint256 leafCount = rawSize / LEAF_SIZE;
        uint256 rootId = nextRootId[setId]++;
        sumTreeAdd(setId, leafCount, rootId);
        rootCids[setId][rootId] = root;
        rootLeafCounts[setId][rootId] = leafCount;
        proofSetLeafCount[setId] += leafCount;
        return rootId;
    }

    // removeRoot removes a root from a proof set. Must be called by the contract owner.
    function removeRoot(uint256 setId, uint256 rootId) public {
        require(proofSetOwner[setId] == msg.sender, "Only the owner can remove roots");
        // TODO: implement me
    }

    // findRoot returns the root id for a given leaf index and the leaf's offset within
    // the rootId.
    // 
    // It does this by running a binary search over the logical array
    // To do this efficiently we walk the sumtree.
    function findRootId(uint256 setId, uint256 leafIndex) public view returns (uint256, uint256) { 
        require(leafIndex < proofSetLeafCount[setId], "Leaf index out of bounds");
        // The top of the sumtree is the largest power of 2 less than the number of roots
        uint256 top = 256 - BitOps.clz(nextRootId[setId]);
        uint256 searchPtr = (1 << top) - 1;
        uint256 acc = 0;

        // Binary search until we find the index of the sumtree leaf covering the index range
        uint256 candidate;
        for (uint256 h = top; h > 0; h--) {
            // Search has taken us past the end of the sumtree
            // Only option is to go left
            if (searchPtr >= nextRootId[setId]) {
                searchPtr -= 1 << (h - 1);
                continue;
            }

            candidate = acc + sumTreeCounts[setId][searchPtr]; 
            // Go right            
            if (candidate <= leafIndex) { 
                acc += sumTreeCounts[setId][searchPtr];
                searchPtr += 1 << (h - 1);
            } else {
                // Go left
                searchPtr -= 1 << (h - 1);
            }
        }
        candidate = acc + sumTreeCounts[setId][searchPtr];
        if (candidate <= leafIndex) {
            // Choose right 
            return (searchPtr + 1, leafIndex - candidate); 
        } // Choose left
        return (searchPtr, leafIndex - acc);
    }


    // Verifies and records that the provider proved possession of the 
    // proof set Merkle roots at some epoch. The challenge seed is determined 
    // by the previous proof of possession
    // TODO: proof will probably be a new type not just bytes
    function provePossession(uint256 setId, bytes calldata proof) public {
        // TODO: implement me
        // TODO: ownership check for proof validation? I don't think its necessary but maybe useful? 
    }

    /* Sum tree functions */
    /* 
    A sumtree is a variant of a Fenwick or binary indexed tree.  It is a binary
    tree where each node is the sum of its children. It is designed to support
    efficient query and update operations on a base array of integers. Here 
    the base array is the roots leaf count array.  Asymptotically the sum tree 
    has logarithmic search and update functions.  Each slot of the sum tree is
    logically a node in a binary tree. 
     
    The node’s height from the leaf depth is defined as -1 + the ruler function
    (https://oeis.org/A001511 [0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,...]) applied to 
    the slot’s index + 1, i.e. the number of trailing 0s in the binary representation
    of the index + 1.  Each slot in the sum tree array contains the sum of a range
    of the base array.  The size of this range is defined by the height assigned
    to this slot in the binary tree structure of the sum tree, i.e. the value of
    the ruler function applied to the slot’s index.  The range for height d and 
    current index j is [j + 1 - 2^d : j] inclusive.  For example if the node’s
    height is 0 its value is set to the base array’s value at the same index and
    If the node’s height is 3 then its value is set to the sum of the last 2^3 = 8
    values of the base array. The reason to do things with recursive partial sums
    is to accommodate O(log len(base array)) updates for add and remove operations
    on the base array.
    */


    // Perform sumtree addition 
    // 
    function sumTreeAdd(uint256 setId, uint256 count, uint256 rootId) internal {
        uint256 index = rootId;
        uint256 h = heightFromIndex(index);
        
        uint256 sum = count;
        // Sum BaseArray[j - 2^i] for i in [0, h)
        for (uint256 i = 0; i < h; i++) {
            uint256 j = index - (1 << i);
            sum += sumTreeCounts[setId][j];
        }
        sumTreeCounts[setId][rootId] = sum;        
    }

    // Return height of sumtree node at given index
    // Calculated by taking the trailing zeros of 1 plus the index
    function heightFromIndex(uint256 index) internal pure returns (uint256) {
        return BitOps.ctz(index + 1);
    }

}
