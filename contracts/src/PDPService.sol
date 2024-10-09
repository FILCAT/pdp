// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BitOps} from "../src/BitOps.sol";
import {Cids} from "../src/Cids.sol";
import {MerkleVerify} from "../src/Proofs.sol";
import {PDPRecordKeeper} from "../src/PDPRecordKeeper.sol";

contract PDPService {
    // Constants
    uint256 public constant LEAF_SIZE = 32;
    uint256 public constant MAX_ROOT_SIZE = 1 << 50;

    // Events
    event ProofSetCreated(uint256 indexed setId);
    event RootsAdded(uint256 indexed firstAdded);
    event RootsRemoved(uint256 indexed totalDelta);


    // Types

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
        nextChallengeEpoch: uint64;
        recordKeeper: address;
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
    mapping(uint256 => mapping(uint256 => Cids.Cid)) rootCids; 
    mapping(uint256 => mapping(uint256 => uint256)) rootLeafCounts;
    mapping(uint256 => mapping(uint256 => uint256)) sumTreeCounts;
    mapping(uint256 => uint256) nextRootId;
    mapping(uint256 => uint256) proofSetLeafCount;
    mapping(uint256 => uint256) nextChallengeEpoch;
    mapping(uint256 => address) proofSetRecordKeeper;
    // ownership of proof set is initialized upon creation to create message sender 
    // proofset owner has exclusive permission to add and remove roots and delete the proof set
    mapping(uint256 => address) proofSetOwner;
    mapping(uint256 => address) proofSetProposedOwner;
    

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

    // Returns the next challenge epoch for a proof set
    function getNextChallengeEpoch(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return nextChallengeEpoch[setId];
    }

    // Returns the owner of a proof set and the proposed owner if any
    function getProofSetOwner(uint256 setId) public view returns (address, address) {
        require(proofSetLive(setId), "Proof set not live");
        return (proofSetOwner[setId], proofSetProposedOwner[setId]);
    }

    // Returns the root CID for a given proof set and root ID
    function getRootCid(uint256 setId, uint256 rootId) public view returns (Cids.Cid memory) {
        require(proofSetLive(setId), "Proof set not live");
        return rootCids[setId][rootId];
    }

    // Returns the root leaf count for a given proof set and root ID
    function getRootLeafCount(uint256 setId, uint256 rootId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return rootLeafCounts[setId][rootId];
    }

    // owner proposes new owner.  If the owner proposes themself delete any outstanding proposed owner
    function proposeProofSetOwner(uint256 setId, address newOwner) public {
        require(proofSetLive(setId), "Proof set not live");
        address owner = proofSetOwner[setId];
        require(owner == msg.sender, "Only the current owner can propose a new owner");
        if (owner == newOwner) {
            // If the owner proposes themself delete any outstanding proposed owner
            delete proofSetProposedOwner[setId];
        } else {
            proofSetProposedOwner[setId] = newOwner;
        }
    }

    function claimProofSetOwnership(uint256 setId) public {
        require(proofSetLive(setId), "Proof set not live");
        require(proofSetProposedOwner[setId] == msg.sender, "Only the proposed owner can claim ownership");
        proofSetOwner[setId] = msg.sender;
        delete proofSetProposedOwner[setId];
    }


    // A proof set is created empty, with no roots. Creation yields a proof set ID 
    // for referring to the proof set later.
    // Sender of create message is proof set owner.
    function createProofSet(address recordKeeper) public returns (uint256) {
        uint256 setId = nextProofSetId++;
        proofSetLeafCount[setId] = 0;
        nextChallengeEpoch[setId] = 0;  // Re-initialized when the first root is added.
        proofSetOwner[setId] = msg.sender;
        proofSetRecordKeeper[setId] = recordKeeper;

        bytes memory extraData = abi.encode(msg.sender);
        _addRecord(setId, recordKeeper, PDPRecordKeeper.OperationType.CREATE, extraData);
        emit ProofSetCreated(setId);
        return setId;
    }

    // Removes a proof set. Must be called by the contract owner.   
    function deleteProofSet(uint256 setId) public {
        if (setId >= nextProofSetId) {
            revert("proof set id out of bounds");
        }

        require(proofSetOwner[setId] == msg.sender, "Only the owner can delete proof sets");
        uint256 deletedLeafCount = proofSetLeafCount[setId];
        proofSetLeafCount[setId] = 0;
        proofSetOwner[setId] = address(0);
        nextChallengeEpoch[setId] = 0;

        bytes memory extraData = abi.encode(deletedLeafCount);
        _addRecord(setId, proofSetRecordKeeper[setId], PDPRecordKeeper.OperationType.DELETE, extraData);
    }

    // Struct for tracking root data
    struct RootData {
        Cids.Cid root;
        uint256 rawSize;
    }

    function addRoots(uint256 setId, RootData[] calldata rootData) public returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        require(rootData.length > 0, "Must add at least one root");
        require(proofSetOwner[setId] == msg.sender, "Only the owner can add roots");
        bool needsChallengeEpoch = nextChallengeEpoch[setId] == 0;
        uint256 firstAdded = nextRootId[setId];

        for (uint256 i = 0; i < rootData.length; i++) {
            addOneRoot(setId, i, rootData[i].root, rootData[i].rawSize);
        }
        // Initialise the first challenge epoch when the first data is added.
        if (needsChallengeEpoch) {
            nextChallengeEpoch[setId] = block.number + challengeFinality; 
        }

        bytes memory extraData = abi.encode(firstAdded, rootData);
        _addRecord(setId, proofSetRecordKeeper[setId], PDPRecordKeeper.OperationType.ADD, extraData);
        emit RootsAdded(firstAdded);
        return firstAdded;
    }

    error IndexedError(uint256 idx, string msg);

    // Appends a new root to the collection managed by a proof set.
    // Must be called by the proof set owner.  
    function addOneRoot(uint256 setId, uint256 callIdx, Cids.Cid calldata root, uint256 rawSize) internal returns (uint256) {
        if (rawSize % LEAF_SIZE != 0) {
            revert IndexedError(callIdx, "Size must be a multiple of 32");
        }
        if (rawSize == 0) {
            revert IndexedError(callIdx, "Size must be greater than 0");
        }
        if (rawSize > MAX_ROOT_SIZE) {
            revert IndexedError(callIdx, "Root size must be less than 2^50");
        }

        uint256 leafCount = rawSize / LEAF_SIZE;
        uint256 rootId = nextRootId[setId]++;
        sumTreeAdd(setId, leafCount, rootId);
        rootCids[setId][rootId] = root;
        rootLeafCounts[setId][rootId] = leafCount;
        proofSetLeafCount[setId] += leafCount;
        return rootId;
    }

    // removeRoots removes a batch of roots from a proof set.  Must be called by the proof set owner.
    // returns the total removed leaf count
    function removeRoots(uint256 setId, uint256[] calldata rootIds) public returns (uint256){
        require(proofSetOwner[setId] == msg.sender, "Only the owner can remove roots");
        require(proofSetLive(setId), "Proof set not live");
        uint256 totalDelta = 0;
        for (uint256 i = 0; i < rootIds.length; i++){
            totalDelta += removeOneRoot(setId, rootIds[i]);
        }
        proofSetLeafCount[setId] -= totalDelta;
        // Clear next challenge epoch if the set is now empty.
        // It will be re-set when new data is added.
        if (proofSetLeafCount[setId] == 0) {
            nextChallengeEpoch[setId] = 0;
        }

        bytes memory extraData = abi.encode(totalDelta, rootIds);
        _addRecord(setId, proofSetRecordKeeper[setId], PDPRecordKeeper.OperationType.REMOVE, extraData);
        emit RootsRemoved(totalDelta);
        return totalDelta;
    }

    // removeOneRoot removes a root from a proof set. 
    function removeOneRoot(uint256 setId, uint256 rootId) internal returns (uint256) {
        uint256 delta = rootLeafCounts[setId][rootId];
        sumTreeRemove(setId, rootId, delta);
        delete rootLeafCounts[setId][rootId];
        delete rootCids[setId][rootId];
        return delta;
    }

    struct RootIdAndOffset {
        uint256 rootId;
        uint256 offset;
    }

    function findOneRootId(uint256 setId, uint256 leafIndex, uint256 top) internal view returns (RootIdAndOffset memory) { 
        require(leafIndex < proofSetLeafCount[setId], "Leaf index out of bounds");
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
            return RootIdAndOffset(searchPtr + 1, leafIndex - candidate); 
        } // Choose left
        return RootIdAndOffset(searchPtr, leafIndex - acc);
    }

    // findRoot returns the root id for a given leaf index and the leaf's offset within
    // the rootId.
    // 
    // It does this by running a binary search over the logical array
    // To do this efficiently we walk the sumtree.
    function findRootIds(uint256 setId, uint256[] calldata leafIndexs) public view returns (RootIdAndOffset[] memory) { 
        // The top of the sumtree is the largest power of 2 less than the number of roots
        uint256 top = 256 - BitOps.clz(nextRootId[setId]);
        RootIdAndOffset[] memory result = new RootIdAndOffset[](leafIndexs.length);
        for (uint256 i = 0; i < leafIndexs.length; i++) {
            result[i] = findOneRootId(setId, leafIndexs[i], top);
        }
        return result;
    }

    struct Proof {
        bytes32 leaf;
        bytes32[] proof;
    }

    // Verifies and records that the provider proved possession of the 
    // proof set Merkle roots at some epoch. The challenge seed is determined 
    // by the epoch of the previous proof of possession.
    // Note that this method is not restricted to the proof set owner.
    function provePossession(uint256 setId, Proof[] calldata proofs) public {
        uint256 challengeEpoch = nextChallengeEpoch[setId];
        require(block.number >= challengeEpoch, "premature proof");
        require(proofs.length > 0, "empty proof");

        // TODO: fetch proper seed from chain randomness, https://github.com/FILCAT/pdp/issues/44
        uint256 seed = challengeEpoch;
        uint256 leafCount = getProofSetLeafCount(setId);
        uint256 sumTreeTop = 256 - BitOps.clz(nextRootId[setId]);


        for (uint64 i = 0; i < proofs.length; i++) {
            // Hash (SHA3) the seed,  proof set id, and proof index to create challenge.
            bytes memory payload = abi.encodePacked(seed, setId, i);
            uint256 challengeIdx = uint256(keccak256(payload)) % leafCount;

            // Find the root that has this leaf, and the offset of the leaf within that root.
            RootIdAndOffset memory root = findOneRootId(setId, challengeIdx, sumTreeTop);
            bytes32 rootHash = Cids.digestFromCid(getRootCid(setId, root.rootId));
            bool ok = MerkleVerify.verify(proofs[i].proof, rootHash, proofs[i].leaf, root.offset);
            require(ok, "proof did not verify");
        }

        // Set the next challenge epoch.
        nextChallengeEpoch[setId] = block.number + challengeFinality; 
        bytes memory extraData = abi.encode(proofSetLeafCount[setId], seed);
        _addRecord(setId, proofSetRecordKeeper[setId], PDPRecordKeeper.OperationType.PROVE_POSSESSION, extraData);
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

    // Perform sumtree removal
    //
    function sumTreeRemove(uint256 setId, uint256 index, uint256 delta) internal {
        uint256 top = uint256(256 - BitOps.clz(nextRootId[setId]));
        uint256 h = uint256(heightFromIndex(index));

        // Deletion traversal either terminates at 
        // 1) the top of the tree or
        // 2) the highest node right of the removal index
        while (h <= top && index < nextRootId[setId]) {
            sumTreeCounts[setId][index] -= delta;
            index += 1 << h;
            h = heightFromIndex(index);
        }
    }

    // Return height of sumtree node at given index
    // Calculated by taking the trailing zeros of 1 plus the index
    function heightFromIndex(uint256 index) internal pure returns (uint256) {
        return BitOps.ctz(index + 1);
    }

    /* Record keeper functions */
    function _addRecord(uint256 proofSetId, address recordKeeper, PDPRecordKeeper.OperationType operationType, bytes memory extraData) internal {
        require(address(recordKeeper) != address(0), "Record keeper must be set");
        PDPRecordKeeper(recordKeeper).addRecord(proofSetId, uint64(block.number), operationType, extraData);
    }

}
