pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";
import {PDPService} from "../src/PDPService.sol";
import {MerkleProve} from "../src/Proofs.sol";
import {ProofUtil} from "./ProofUtil.sol";
import {PDPRecordKeeperApplication, PDPApplication} from "../src/PDPRecordKeeperApplication.sol";


contract PDPServiceProofSetCreateDeleteTest is Test {
    PDPService pdpService;
    PDPRecordKeeperApplication recordKeeper;
    RecordKeeperHelper recordAssert;

    function setUp() public {
        pdpService = new PDPService(2);
        recordKeeper = new PDPRecordKeeperApplication(address(pdpService));
        recordAssert = new RecordKeeperHelper(address(recordKeeper));
    }
    function tearDown() public view {
        recordAssert.assertAllRecords();
    }

    function testCreateProofSet() public {
        Cids.Cid memory zeroRoot;
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        assertEq(setId, 0, "First proof set ID should be 0");
        assertEq(pdpService.getProofSetLeafCount(setId), 0, "Proof set leaf count should be 0");

        (address owner, address proposedOwner) = pdpService.getProofSetOwner(setId);
        assertEq(owner, address(this), "Proof set owner should be the constructor sender");
        assertEq(proposedOwner, address(0), "Proof set proposed owner should be initialized to zero address");

        assertEq(pdpService.getNextChallengeEpoch(setId), 0, "Proof set challenge epoch should be zero");
        assertEq(pdpService.rootLive(setId, 0), false, "Proof set root should not be live");
        assertEq(pdpService.getRootCid(setId, 0).data, zeroRoot.data, "Uninitialized root should be empty");
        assertEq(pdpService.getRootLeafCount(setId, 0), 0, "Uninitialized root should have zero leaves");
        assertEq(pdpService.getNextChallengeEpoch(setId), 0, "Proof set challenge epoch should be zero");
        tearDown();
    }

    function testDeleteProofSet() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        pdpService.deleteProofSet(setId);
        recordAssert.expectRecord(PDPApplication.OperationType.DELETE, setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetLeafCount(setId);
        tearDown();
    }

    function testOnlyOwnerCanDeleteProofSet() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        // Create a new address to act as a non-owner
        address nonOwner = address(0x1234);
        // Expect revert when non-owner tries to delete the proof set
        vm.prank(nonOwner);
        vm.expectRevert("Only the owner can delete proof sets");
        pdpService.deleteProofSet(setId);

        // Now verify the owner can delete the proof set
        pdpService.deleteProofSet(setId);
        recordAssert.expectRecord(PDPApplication.OperationType.DELETE, setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetOwner(setId);
        tearDown();
    }

    // TODO: once we have addRoots we should test deletion of a non empty proof set
    function testCannotDeleteNonExistentProofSet() public {
        vm.expectRevert("proof set id out of bounds");
        pdpService.deleteProofSet(0);
        tearDown();
    }

    function testMethodsOnDeletedProofSetFails() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        pdpService.deleteProofSet(setId);
        recordAssert.expectRecord(PDPApplication.OperationType.DELETE, setId);
        vm.expectRevert("Only the owner can delete proof sets");
        pdpService.deleteProofSet(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetOwner(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getProofSetLeafCount(setId);
        vm.expectRevert("Proof set not live");
        pdpService.getRootCid(setId, 0);
        vm.expectRevert("Proof set not live");
        pdpService.getRootLeafCount(setId, 0);
        vm.expectRevert("Proof set not live");
        pdpService.getNextChallengeEpoch(setId);
        vm.expectRevert("Proof set not live");
        pdpService.addRoots(setId, new PDPService.RootData[](0));
        tearDown();
    }

    function testGetProofSetID() public {
        pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, 0);
        pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, 1);
        assertEq(2, pdpService.getNextProofSetId(), "Next proof set ID should be 2");
        tearDown();
    }
}

contract PDPServiceOwnershipTest is Test {
    PDPService pdpService;
    PDPRecordKeeperApplication recordKeeper;
    address public owner;
    address public nextOwner;
    address public nonOwner;

    function setUp() public {
        pdpService = new PDPService(2);
        recordKeeper = new PDPRecordKeeperApplication(address(pdpService));

        owner = address(this);
        nextOwner = address(0x1234);
        nonOwner = address(0xffff);
    }

    function testOwnershipTransfer() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        pdpService.proposeProofSetOwner(setId, nextOwner);
        (address ownerStart, address proposedOwnerStart) = pdpService.getProofSetOwner(setId);
        assertEq(ownerStart, owner, "Proof set owner should be the constructor sender");
        assertEq(proposedOwnerStart, nextOwner, "Proof set proposed owner should make the one proposed");
        vm.prank(nextOwner); 
        pdpService.claimProofSetOwnership(setId);
        (address ownerEnd, address proposedOwnerEnd) = pdpService.getProofSetOwner(setId);
        assertEq(ownerEnd, nextOwner, "Proof set owner should be the next owner");
        assertEq(proposedOwnerEnd, address(0), "Proof set proposed owner should be zero address");
    }

    function testOwnershipProposalReset() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        pdpService.proposeProofSetOwner(setId, nextOwner);
        pdpService.proposeProofSetOwner(setId, owner);
        (address ownerEnd, address proposedOwnerEnd) = pdpService.getProofSetOwner(setId);
        assertEq(ownerEnd, owner, "Proof set owner should be the constructor sender");
        assertEq(proposedOwnerEnd, address(0), "Proof set proposed owner should be zero address");
    }

    function testOwnershipPermissionsRequired() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        vm.prank(nonOwner);
        vm.expectRevert("Only the current owner can propose a new owner");
        pdpService.proposeProofSetOwner(setId, nextOwner);

        // Now send proposal from actual owner
        pdpService.proposeProofSetOwner(setId, nextOwner);

        // Proposed owner has no extra permissions
        vm.prank(nextOwner);
        vm.expectRevert("Only the current owner can propose a new owner");
        pdpService.proposeProofSetOwner(setId, nonOwner);

        vm.prank(nonOwner);
        vm.expectRevert("Only the proposed owner can claim ownership");
        pdpService.claimProofSetOwnership(setId);
    }
}

contract PDPServiceProofSetMutateTest is Test {
    uint256 constant challengeFinalityDelay = 2;

    PDPService pdpService;
    PDPRecordKeeperApplication recordKeeper;
    RecordKeeperHelper recordAssert;

    function setUp() public {
        pdpService = new PDPService(challengeFinalityDelay);
        recordKeeper = new PDPRecordKeeperApplication(address(pdpService));
        recordAssert = new RecordKeeperHelper(address(recordKeeper));
    }

    function tearDown() public view {
        recordAssert.assertAllRecords();
    }

    function testAddRoot() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        PDPService.RootData[] memory roots = new PDPService.RootData[](1);
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 64);
        uint256 rootId = pdpService.addRoots(setId, roots);
        recordAssert.expectRecord(PDPApplication.OperationType.ADD, setId);
        
        uint256 leafCount = roots[0].rawSize / 32;
        assertEq(pdpService.getProofSetLeafCount(setId), leafCount);
        assertEq(pdpService.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);

        assertTrue(pdpService.rootLive(setId, rootId));
        assertEq(pdpService.getRootCid(setId, rootId).data, roots[0].root.data);
        assertEq(pdpService.getRootLeafCount(setId, rootId), leafCount);

        assertEq(pdpService.getNextRootId(setId), 1);
        tearDown();
    }

    function testAddMultipleRoots() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        PDPService.RootData[] memory roots = new PDPService.RootData[](2);
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test1")), 64);
        roots[1] = PDPService.RootData(Cids.Cid(abi.encodePacked("test2")), 128);
        uint256 firstId = pdpService.addRoots(setId, roots);
        recordAssert.expectRecord(PDPApplication.OperationType.ADD, setId);
        assertEq(firstId, 0);

        uint256 expectedLeafCount = roots[0].rawSize / 32 + roots[1].rawSize / 32;
        assertEq(pdpService.getProofSetLeafCount(setId), expectedLeafCount);
        assertEq(pdpService.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);

        assertTrue(pdpService.rootLive(setId, firstId));
        assertTrue(pdpService.rootLive(setId, firstId + 1));
        assertEq(pdpService.getRootCid(setId, firstId).data, roots[0].root.data);
        assertEq(pdpService.getRootCid(setId, firstId + 1).data, roots[1].root.data);

        assertEq(pdpService.getRootLeafCount(setId, firstId), roots[0].rawSize / 32);
        assertEq(pdpService.getRootLeafCount(setId, firstId + 1), roots[1].rawSize / 32);
        assertEq(pdpService.getNextRootId(setId), 2);
        tearDown();
    }

    function expectIndexedError(uint256 index, string memory expectedMessage) internal {
        vm.expectRevert(abi.encodeWithSelector(PDPService.IndexedError.selector, index, expectedMessage));
    }

    function testAddBadRoot() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        PDPService.RootData[] memory roots = new PDPService.RootData[](1);

        // Fail when root size is not a multiple of 32
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 63);
        expectIndexedError(0, "Size must be a multiple of 32");
        pdpService.addRoots(setId, roots);

        // Fail when root size is zero
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 0);
        expectIndexedError(0, "Size must be greater than 0");
        pdpService.addRoots(setId, roots);

        // Fail when root size is too large
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), pdpService.MAX_ROOT_SIZE() + 32);
        expectIndexedError(0, "Root size must be less than 2^50");
        pdpService.addRoots(setId, roots);

        // Fail when not adding any roots;
        PDPService.RootData[] memory emptyRoots = new PDPService.RootData[](0);
        vm.expectRevert("Must add at least one root");
        pdpService.addRoots(setId, emptyRoots);

        // Fail when proof set is no longer live
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        pdpService.deleteProofSet(setId);
        vm.expectRevert("Proof set not live");
        pdpService.addRoots(setId, roots);
    }

    function testAddBadRootsBatched() public {
        // Add one bad root, message fails on bad index
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        PDPService.RootData[] memory roots = new PDPService.RootData[](4);
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        roots[1] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        roots[2] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        roots[3] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 31);

        expectIndexedError(3, "Size must be a multiple of 32");
        pdpService.addRoots(setId, roots);

        // Add multiple bad roots, message fails on first bad index
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 63);
        expectIndexedError(0, "Size must be a multiple of 32");
        pdpService.addRoots(setId, roots);
    }

    function testRemoveRoot() public {
        // Add one root
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        PDPService.RootData[] memory roots = new PDPService.RootData[](1);
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpService.addRoots(setId, roots);
        recordAssert.expectRecord(PDPApplication.OperationType.ADD, setId);

        // Remove root
        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 0;
        pdpService.removeRoots(setId, toRemove);
        recordAssert.expectRecord(PDPApplication.OperationType.REMOVE, setId);

        assertEq(pdpService.rootLive(setId, 0), false);
        assertEq(pdpService.getNextRootId(setId), 1);
        assertEq(pdpService.getProofSetLeafCount(setId), 0);
        assertEq(pdpService.getNextChallengeEpoch(setId), 0);
        bytes memory emptyCidData = new bytes(0);
        assertEq(pdpService.getRootCid(setId, 0).data, emptyCidData);
        assertEq(pdpService.getRootLeafCount(setId, 0), 0);
    }

    function testRemoveRootBatch() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        PDPService.RootData[] memory roots = new PDPService.RootData[](3);
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test1")), 64);
        roots[1] = PDPService.RootData(Cids.Cid(abi.encodePacked("test2")), 64);
        roots[2] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpService.addRoots(setId, roots);
        recordAssert.expectRecord(PDPApplication.OperationType.ADD, setId);
        uint256[] memory toRemove = new uint256[](2);
        toRemove[0] = 0;
        toRemove[1] = 2;
        pdpService.removeRoots(setId, toRemove);
        recordAssert.expectRecord(PDPApplication.OperationType.REMOVE, setId);

        assertEq(pdpService.rootLive(setId, 0), false);
        assertEq(pdpService.rootLive(setId, 1), true);
        assertEq(pdpService.rootLive(setId, 2), false);

        assertEq(pdpService.getNextRootId(setId), 3);
        assertEq(pdpService.getProofSetLeafCount(setId), 64/32);
        assertEq(pdpService.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);

        bytes memory emptyCidData = new bytes(0);
        assertEq(pdpService.getRootCid(setId, 0).data, emptyCidData);
        assertEq(pdpService.getRootCid(setId, 1).data, roots[1].root.data);
        assertEq(pdpService.getRootCid(setId, 2).data, emptyCidData);

        assertEq(pdpService.getRootLeafCount(setId, 0), 0);
        assertEq(pdpService.getRootLeafCount(setId, 1), 64/32);
        assertEq(pdpService.getRootLeafCount(setId, 2), 0);

    }
    
    function testRemoveBadRootDoesntFail() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        PDPService.RootData[] memory roots = new PDPService.RootData[](1);
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpService.addRoots(setId, roots);
        recordAssert.expectRecord(PDPApplication.OperationType.ADD, setId);
        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 1;
        pdpService.removeRoots(setId, toRemove);

        toRemove[0] = 0;
        pdpService.removeRoots(setId, toRemove);
        recordAssert.expectRecord(PDPApplication.OperationType.REMOVE, setId);
        assertEq(false, pdpService.rootLive(setId, 0));

        // Removing again fails
        pdpService.removeRoots(setId, toRemove);
        assertEq(false, pdpService.rootLive(setId, 0));

    }
}

contract PDPServiceProofTest is Test {
    uint256 constant challengeFinalityDelay = 2;
    string constant cidPrefix = "CID";
    PDPService pdpService;
    PDPRecordKeeperApplication recordKeeper;
    RecordKeeperHelper recordAssert;

    function setUp() public {
        pdpService = new PDPService(challengeFinalityDelay);
        recordKeeper = new PDPRecordKeeperApplication(address(pdpService));
        recordAssert = new RecordKeeperHelper(address(recordKeeper));
    }

    function tearDown() public view {
        recordAssert.assertAllRecords();
    }

    function testProveSingleRoot() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpService.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with  multiple challenges to single tree.
        uint challengeCount = 3;
        PDPService.Proof[] memory proofs = buildProofsForSingleton(setId, challengeCount, tree, leafCount);

        // Submit proof.
        pdpService.provePossession(setId, proofs);
        recordAssert.expectRecord(PDPApplication.OperationType.PROVE_POSSESSION, setId);
        // Verify the next challenge is in a subsequent epoch.
        assertEq(pdpService.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);
        tearDown();
    }

    function testLateProofAccepted() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(10);

        // Advance chain short of challenge epoch
        uint256 challengeEpoch = pdpService.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch + 100);

        // Build a proof.
        PDPService.Proof[] memory proofs = buildProofsForSingleton(setId, 1, tree, leafCount);

        // Submit proof.
        pdpService.provePossession(setId, proofs);
        recordAssert.expectRecord(PDPApplication.OperationType.PROVE_POSSESSION, setId);
        assertEq(pdpService.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);
        assertEq(pdpService.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);
        tearDown();
    }

    function testEarlyProofRejected() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(10);

        // Advance chain short of challenge epoch
        uint256 challengeEpoch = pdpService.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch - 1);

        // Build a proof.
        PDPService.Proof[] memory proofs = buildProofsForSingleton(setId, 1, tree, leafCount);

        // Submit proof.
        vm.expectRevert();
        pdpService.provePossession(setId, proofs);
        tearDown();
    }

    function testEmptyProofRejected() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        PDPService.Proof[] memory emptyProof = new PDPService.Proof[](0);

        // Rejected with no roots
        vm.expectRevert();
        pdpService.provePossession(setId, emptyProof);

        addOneRoot(setId, 10);

        // Rejected with a root
        vm.expectRevert();
        pdpService.provePossession(setId, emptyProof);
        tearDown();
    }

    function testBadChallengeRejected() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(10);

        // Make a proof that's good for this challenge epoch.
        uint256 challengeEpoch = pdpService.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        PDPService.Proof[] memory proofs = buildProofsForSingleton(setId, 1, tree, leafCount);

        // Submit proof successfully, advancing the proof set to a new challenge epoch.
        pdpService.provePossession(setId, proofs);
        recordAssert.expectRecord(PDPApplication.OperationType.PROVE_POSSESSION, setId);

        uint nextChallengeEpoch = pdpService.getNextChallengeEpoch(setId);
        assertNotEq(nextChallengeEpoch, challengeEpoch);
        vm.roll(nextChallengeEpoch);
        
        // The proof for the old challenge epoch should no longer be valid.
        vm.expectRevert();
        pdpService.provePossession(setId, proofs);
        tearDown();
    }

    function testBadRootsRejected() public {
        uint[] memory leafCounts = new uint[](2);
        // Note: either co-prime leaf counts or a challenge count > 1 are required for this test to demonstrate the failing proof.
        // With a challenge count == 1 and leaf counts e.g. 10 and 20 it just so happens that the first computed challenge index is the same 
        // (lying in the first root) whether the tree has one or two roots.
        // This could be prevented if the challenge index calculation included some marker of proof set contents, like
        // a hash of all the roots or an edit sequence number.
        leafCounts[0] = 7;
        leafCounts[1] = 13;
        bytes32[][][] memory trees = new bytes32[][][](2);
        // Make proof set initially with one root.
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(leafCounts[0]);
        trees[0] = tree;

        // Make a proof that's good for the single root.
        uint256 challengeEpoch = pdpService.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        uint challengeCount = 1;
        PDPService.Proof[] memory proofsOneRoot = buildProofsForSingleton(setId, challengeCount, trees[0], leafCounts[0]);

        // Add another root before submitting the proof.
        uint256 newRootId;
        (trees[1], newRootId) = addOneRoot(setId, leafCounts[1]);
        
        // The proof for one root should be invalid against the set with two.
        vm.expectRevert();
        pdpService.provePossession(setId, proofsOneRoot);

        // Make a new proof that is valid with two roots
        PDPService.Proof[] memory proofsTwoRoots = buildProofs(setId, challengeCount, trees, leafCounts);
        uint256[] memory removeRoots = new uint256[](1);
        removeRoots[0] = newRootId;
        pdpService.removeRoots(setId, removeRoots);
        recordAssert.expectRecord(PDPApplication.OperationType.REMOVE, setId);

        // The proof for two roots should be invalid against the set with one.
        vm.expectRevert();
        pdpService.provePossession(setId, proofsTwoRoots);

        // But the single root proof is now good again.
        pdpService.provePossession(setId, proofsOneRoot);
        recordAssert.expectRecord(PDPApplication.OperationType.PROVE_POSSESSION, setId);
        tearDown();
    }

    function testProveManyRoots() public {
        uint[] memory leafCounts = new uint[](3);
        // Pick a distinct size  for each tree (up to some small maximum size).
        for (uint i = 0; i < leafCounts.length; i++) {
            leafCounts[i] = uint256(sha256(abi.encode(i))) % 64;
        }

        (uint256 setId, bytes32[][][] memory trees) = makeProofSetWithRoots(leafCounts);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpService.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with multiple challenges to span the roots.
        uint challengeCount = 11;
        PDPService.Proof[] memory proofs = buildProofs(setId, challengeCount, trees, leafCounts);
        // Submit proof.
        pdpService.provePossession(setId, proofs);
        recordAssert.expectRecord(PDPApplication.OperationType.PROVE_POSSESSION, setId);
        // Verify the next challenge is in a subsequent epoch.
        assertEq(pdpService.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);
        tearDown();
    }


    ///// Helpers /////

    // Initializes a new proof set, generates trees of specified sizes, and adds roots to the set.
    function makeProofSetWithRoots(uint[] memory leafCounts) internal returns (uint256, bytes32[][][]memory) {
        // Create trees and their roots.
        bytes32[][][] memory trees = new bytes32[][][](leafCounts.length);
        PDPService.RootData[] memory roots = new PDPService.RootData[](leafCounts.length);
        for (uint i = 0; i < leafCounts.length; i++) {
            // Generate a uniquely-sized tree for each root (up to some small maximum size).
            trees[i] = ProofUtil.makeTree(leafCounts[i]);
            roots[i] = makeRoot(trees[i], leafCounts[i]);
        }

        // Create new proof set and add roots.
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        recordAssert.expectRecord(PDPApplication.OperationType.CREATE, setId);
        pdpService.addRoots(setId, roots);
        recordAssert.expectRecord(PDPApplication.OperationType.ADD, setId);
        return (setId, trees);
    }

    // Initializes a new proof set and adds a single generated tree.
    function makeProofSetWithOneRoot(uint leafCount) internal returns (uint256, bytes32[][]memory) {
         uint[] memory leafCounts = new uint[](1);
        leafCounts[0] = leafCount;
        (uint256 setId, bytes32[][][] memory trees) = makeProofSetWithRoots(leafCounts);
        return (setId, trees[0]);
    }

    // Creates a tree and adds it to a proof set.
    // Returns the Merkle tree and root.
    function addOneRoot(uint256 setId, uint leafCount) internal returns (bytes32[][] memory, uint256) {
        bytes32[][] memory tree = ProofUtil.makeTree(leafCount);
        PDPService.RootData[] memory roots = new PDPService.RootData[](1);
        roots[0] = makeRoot(tree, leafCount);
        uint256 rootId = pdpService.addRoots(setId, roots);
        recordAssert.expectRecord(PDPApplication.OperationType.ADD, setId);
        return (tree, rootId);
    }

    // Constructs a RootData structure for a Merkle tree.
    function makeRoot(bytes32[][] memory tree, uint leafCount) internal pure returns (PDPService.RootData memory) {
        return PDPService.RootData(Cids.cidFromDigest(bytes(cidPrefix), tree[0][0]), leafCount * 32);
    }

    // Builds a proof of posession for a proof set
    function buildProofs(uint256 setId, uint challengeCount, bytes32[][][] memory trees, uint[] memory leafCounts) internal view returns (PDPService.Proof[] memory) {
        uint256 challengeEpoch = pdpService.getNextChallengeEpoch(setId);
        uint256 seed = challengeEpoch; // Seed is (temporarily) the challenge epoch
        uint totalLeafCount = 0;
        for (uint i = 0; i < leafCounts.length; ++i) {
            totalLeafCount += leafCounts[i];
        }
        
        PDPService.Proof[] memory proofs = new PDPService.Proof[](challengeCount);
        for (uint challengeIdx = 0; challengeIdx < challengeCount; challengeIdx++) {
            // Compute challenge index
            bytes memory payload = abi.encodePacked(seed, setId, uint64(challengeIdx));
            uint256 challengeOffset = uint256(keccak256(payload)) % totalLeafCount;

            uint treeIdx = 0;
            uint256 treeOffset = 0;
            for (uint i = 0; i < leafCounts.length; ++i) {
                if (leafCounts[i] > challengeOffset) {
                    treeIdx = i;
                    treeOffset = challengeOffset;
                    break;
                } else {
                    challengeOffset -= leafCounts[i];
                }
            }

            bytes32[][] memory tree = trees[treeIdx];
            bytes32[] memory path = MerkleProve.buildProof(tree, treeOffset);
            proofs[challengeIdx] = PDPService.Proof(tree[tree.length - 1][treeOffset], path);

            // console.log("Leaf", vm.toString(proofs[0].leaf));
            // console.log("Proof");
            // for (uint j = 0; j < proofs[0].proof.length; j++) {
            //     console.log(vm.toString(j), vm.toString(proofs[0].proof[j]));
            // }
        }

        return proofs;
    }

    // Builds a proof of posesesion for a proof set with a single root.
    function buildProofsForSingleton(uint256 setId, uint challengeCount, bytes32[][] memory tree, uint leafCount) internal view returns (PDPService.Proof[] memory) {
        bytes32[][][] memory trees = new bytes32[][][](1);
        trees[0] = tree;
        uint[] memory leafCounts = new uint[](1);
        leafCounts[0] = leafCount;
        PDPService.Proof[] memory proofs = buildProofs(setId, challengeCount, trees, leafCounts);
        return proofs;
    }
}

contract SumTreeInternalTestPDPService is PDPService {
    constructor(uint256 _challengeFinality) PDPService(_challengeFinality) {}

    function testHeightFromIndex(uint256 index) public pure returns (uint256) {
        return heightFromIndex(index);
    }

    function getSumTreeCounts(uint256 setId, uint256 rootId) public view returns (uint256) {
        return sumTreeCounts[setId][rootId];
    }
}

contract SumTreeHeightTest is Test {
    SumTreeInternalTestPDPService pdpService;

    function setUp() public {
        pdpService = new SumTreeInternalTestPDPService(2);
    }

    function testHeightFromIndex() public view {
        // https://oeis.org/A001511
        uint8[105] memory oeisA001511 = [
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 6, 
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 7, 
            1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1, 6, 
            1, 2, 1, 3, 1, 2, 1, 4, 1
        ];
        for (uint256 i = 0; i < 105; i++) {
            assertEq(uint256(oeisA001511[i]), pdpService.testHeightFromIndex(i) + 1, "Heights from index 0 to 104 should match OEIS A001511");
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/PDPService.sol";

contract SumTreeAddTest is Test {
    SumTreeInternalTestPDPService pdpService;
    PDPRecordKeeperApplication recordKeeper;
    uint256 testSetId;

    function setUp() public {
        pdpService = new SumTreeInternalTestPDPService(100); // Assuming 100 as challengeFinality
        recordKeeper = new PDPRecordKeeperApplication(address(pdpService));
        testSetId = pdpService.createProofSet(address(recordKeeper));
    }

    function testMultiAdd() public {
        uint256[] memory counts = new uint256[](8);
        counts[0] = 1;
        counts[1] = 2;
        counts[2] = 3;
        counts[3] = 5;
        counts[4] = 8;
        counts[5] = 13;
        counts[6] = 21;
        counts[7] = 34;

        PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](8);

        for (uint256 i = 0; i < counts.length; i++) {
            Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test", i));
            rootDataArray[i] = PDPService.RootData(testCid, counts[i] * pdpService.LEAF_SIZE());
        }
        pdpService.addRoots(testSetId, rootDataArray);
        assertEq(pdpService.getProofSetLeafCount(testSetId), 87, "Incorrect final proof set leaf count");
        assertEq(pdpService.getNextRootId(testSetId), 8, "Incorrect next root ID");
        assertEq(pdpService.getSumTreeCounts(testSetId, 7), 87, "Incorrect sum tree count");
        assertEq(pdpService.getRootLeafCount(testSetId, 7), 34, "Incorrect root leaf count");
        Cids.Cid memory expectedCid = Cids.Cid(abi.encodePacked("test", uint256(3)));
        Cids.Cid memory actualCid = pdpService.getRootCid(testSetId, 3);
        assertEq(actualCid.data, expectedCid.data, "Incorrect root CID");
    }

    function setUpTestingArray() public returns (uint256[] memory counts, uint256[] memory expectedSumTreeCounts) {
        counts = new uint256[](8);
        counts[0] = 200;
        counts[1] = 100;
        counts[2] = 1; // Remove
        counts[3] = 30;
        counts[4] = 50;
        counts[5] = 1; // Remove
        counts[6] = 400;
        counts[7] = 40;

        // Correct sum tree values assuming that rootIdsToRemove are deleted
        expectedSumTreeCounts = new uint256[](8);
        expectedSumTreeCounts[0] = 200;
        expectedSumTreeCounts[1] = 300;
        expectedSumTreeCounts[2] = 0;
        expectedSumTreeCounts[3] = 330;
        expectedSumTreeCounts[4] = 50;
        expectedSumTreeCounts[5] = 50;
        expectedSumTreeCounts[6] = 400;
        expectedSumTreeCounts[7] = 820;

        uint256[] memory rootIdsToRemove = new uint256[](2);
        rootIdsToRemove[0] = 2;
        rootIdsToRemove[1] = 5;

        // Add all
        for (uint256 i = 0; i < counts.length; i++) {
            Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test", i));
            PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
            rootDataArray[0] = PDPService.RootData(testCid, counts[i] * pdpService.LEAF_SIZE());
            pdpService.addRoots(testSetId, rootDataArray);
            // Assert the root was added correctly
            assertEq(pdpService.getRootCid(testSetId, i).data, testCid.data, "Root not added correctly");
        }

        // Delete some
        // Remove roots in batch
        pdpService.removeRoots(testSetId, rootIdsToRemove);
        for (uint256 i = 0; i < rootIdsToRemove.length; i++) {
            bytes memory zeroBytes;
            assertEq(pdpService.getRootCid(testSetId, rootIdsToRemove[i]).data, zeroBytes);
            assertEq(pdpService.getRootLeafCount(testSetId, rootIdsToRemove[i]), 0, "Root size should be 0");
        }
    }

    function testSumTree() public {
        (uint256[] memory counts, uint256[] memory expectedSumTreeCounts) = setUpTestingArray();
        // Assert that the sum tree count is correct
        for (uint256 i = 0; i < counts.length; i++) {
            assertEq(pdpService.getSumTreeCounts(testSetId, i), expectedSumTreeCounts[i], "Incorrect sum tree size");
        }

        // Assert final proof set leaf count
        assertEq(pdpService.getProofSetLeafCount(testSetId), 820, "Incorrect final proof set leaf count");
    }

    function testBatchedRemoveRootsOnlyOwner() public {
        uint256 setId = pdpService.createProofSet(address(recordKeeper));
        Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test"));
        PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
        rootDataArray[0] = PDPService.RootData(testCid, 100 * pdpService.LEAF_SIZE());
        pdpService.addRoots(setId, rootDataArray);

        address nonOwner = address(0x1234);
        uint256[] memory rootIdsToRemove = new uint256[](1);
        rootIdsToRemove[0] = 0;

        vm.prank(nonOwner);
        vm.expectRevert("Only the owner can remove roots");
        pdpService.removeRoots(setId, rootIdsToRemove);
    }

    function testFindRootId() public {
        setUpTestingArray();

        // Test findRootId for various positions
        assertFindRootAndOffset(testSetId, 0, 0, 0);
        assertFindRootAndOffset(testSetId, 199, 0, 199);
        assertFindRootAndOffset(testSetId, 200, 1, 0);
        assertFindRootAndOffset(testSetId, 299, 1, 99);
        assertFindRootAndOffset(testSetId, 300, 3, 0);
        assertFindRootAndOffset(testSetId, 329, 3, 29);
        assertFindRootAndOffset(testSetId, 330, 4, 0);
        assertFindRootAndOffset(testSetId, 379, 4, 49);
        assertFindRootAndOffset(testSetId, 380, 6, 0);
        assertFindRootAndOffset(testSetId, 779, 6, 399);
        assertFindRootAndOffset(testSetId, 780, 7, 0);
        assertFindRootAndOffset(testSetId, 819, 7, 39);

        // Test edge cases
        vm.expectRevert("Leaf index out of bounds");
        uint256[] memory outOfBounds = new uint256[](1);
        outOfBounds[0] = 820;
        pdpService.findRootIds(testSetId, outOfBounds);

        vm.expectRevert("Leaf index out of bounds");
        outOfBounds[0] = 1000;
        pdpService.findRootIds(testSetId, outOfBounds);
    }

    function testBatchFindRootId() public {
        setUpTestingArray();
        uint256[] memory searchIndexes = new uint256[](12);
        searchIndexes[0] = 0;
        searchIndexes[1] = 199;
        searchIndexes[2] = 200;
        searchIndexes[3] = 299;
        searchIndexes[4] = 300;
        searchIndexes[5] = 329;
        searchIndexes[6] = 330;
        searchIndexes[7] = 379;
        searchIndexes[8] = 380;
        searchIndexes[9] = 779;
        searchIndexes[10] = 780;
        searchIndexes[11] = 819;

        uint256[] memory expectedRoots = new uint256[](12);
        expectedRoots[0] = 0;
        expectedRoots[1] = 0;
        expectedRoots[2] = 1;
        expectedRoots[3] = 1;
        expectedRoots[4] = 3;
        expectedRoots[5] = 3;
        expectedRoots[6] = 4;
        expectedRoots[7] = 4;
        expectedRoots[8] = 6;
        expectedRoots[9] = 6;
        expectedRoots[10] = 7;
        expectedRoots[11] = 7;

        uint256[] memory expectedOffsets = new uint256[](12);
        expectedOffsets[0] = 0;
        expectedOffsets[1] = 199;
        expectedOffsets[2] = 0;
        expectedOffsets[3] = 99;
        expectedOffsets[4] = 0;
        expectedOffsets[5] = 29;
        expectedOffsets[6] = 0;
        expectedOffsets[7] = 49;
        expectedOffsets[8] = 0;
        expectedOffsets[9] = 399;
        expectedOffsets[10] = 0;
        expectedOffsets[11] = 39;

        assertFindRootsAndOffsets(testSetId, searchIndexes, expectedRoots, expectedOffsets);
    }

    error TestingFindError(uint256 expected, uint256 actual, string msg);

    function assertFindRootAndOffset(uint256 setId, uint256 searchIndex, uint256 expectRootId, uint256 expectOffset) internal view {
        uint256[] memory searchIndices = new uint256[](1);
        searchIndices[0] = searchIndex;
        PDPService.RootIdAndOffset[] memory result = pdpService.findRootIds(setId, searchIndices);
        if (result[0].rootId != expectRootId) {
            revert TestingFindError(expectRootId, result[0].rootId, "unexpected root");
        }
        if (result[0].offset != expectOffset) {
            revert TestingFindError(expectOffset, result[0].offset, "unexpected offset");
        }
    }

    // The batched version of assertFindRootAndOffset
    function assertFindRootsAndOffsets(uint256 setId, uint256[] memory searchIndices, uint256[] memory expectRootIds, uint256[] memory expectOffsets) internal view {
        PDPService.RootIdAndOffset[] memory result = pdpService.findRootIds(setId, searchIndices);
        for (uint256 i = 0; i < searchIndices.length; i++) {
            assertEq(result[i].rootId, expectRootIds[i], "unexpected root");
            assertEq(result[i].offset, expectOffsets[i], "unexpected offset");
        }
    }

    function testFindRootIdTraverseOffTheEdgeAndBack() public {
        uint256[] memory sizes = new uint256[](5);
        sizes[0] = 1; // Remove
        sizes[1] = 1; // Remove 
        sizes[2] = 1; // Remove
        sizes[3] = 1;
        sizes[4] = 1;

        uint256[] memory rootIdsToRemove = new uint256[](3);
        rootIdsToRemove[0] = 0;
        rootIdsToRemove[1] = 1;
        rootIdsToRemove[2] = 2;

        for (uint256 i = 0; i < sizes.length; i++) {
            Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test", i));
            PDPService.RootData[] memory rootDataArray = new PDPService.RootData[](1);
            rootDataArray[0] = PDPService.RootData(testCid, sizes[i] * pdpService.LEAF_SIZE());
            pdpService.addRoots(testSetId, rootDataArray);
        }
        pdpService.removeRoots(testSetId, rootIdsToRemove);

        assertFindRootAndOffset(testSetId, 0, 3, 0);
        assertFindRootAndOffset(testSetId, 1, 4, 0);
    }
}

contract RecordKeeperHelper is Test {
    address recordKeeper;
    mapping(uint256 => bool) public seenSetIds;
    uint256[] public setIds;
    mapping(uint256 => PDPApplication.OperationType[]) public expectedRecords;

    constructor(address _recordKeeper) {
        recordKeeper = _recordKeeper;
    }

    function expectRecord(PDPApplication.OperationType operationType, uint256 setId) public {
        if (!seenSetIds[setId]) {
            setIds.push(setId);
            seenSetIds[setId] = true;
        }

        expectedRecords[setId].push(operationType);
    }

    function assertAllRecords() public view {
        for (uint256 i = 0; i < setIds.length; i++) {
            assertProofSetRecords(setIds[i]);
        }
    }

    function assertProofSetRecords(uint256 setId) public view {
        PDPRecordKeeperApplication.EventRecord[] memory records = PDPRecordKeeperApplication(recordKeeper).listEvents(setId);
        assertEq(expectedRecords[setId].length, records.length, "Incorrect number of records");
        for (uint256 i = 0; i < records.length; i++) {
            assertEq(uint(records[i].operationType), uint(expectedRecords[setId][i]), "Incorrect operation type");
            assertRecordDataFormat(records[i].operationType, records[i].extraData);
        }
    }

    // Assert the data format for each operation type
    // This will need to be updated for all changes to the data format externalized to the record keeper
    function assertRecordDataFormat(PDPApplication.OperationType operationType, bytes memory extraData) internal pure {
        if (operationType == PDPApplication.OperationType.CREATE) {
            abi.decode(extraData, (address));
        } else if (operationType == PDPApplication.OperationType.ADD) {
            abi.decode(extraData, (uint256,PDPService.RootData[]));
        } else if (operationType == PDPApplication.OperationType.REMOVE) {
            (uint256 totalDelta, uint256[] memory rootIds) = abi.decode(extraData, (uint256, uint256[]));
            require(rootIds.length > 0, "REMOVE: rootIds should not be empty");
            require(totalDelta > 0, "REMOVE: totalDelta should be > 0");
        } else if (operationType == PDPApplication.OperationType.PROVE_POSSESSION) {
            abi.decode(extraData, (uint256, uint256));
        } else if (operationType == PDPApplication.OperationType.DELETE) {
            abi.decode(extraData, (uint256));
        } else {
            revert("Unknown operation type");
        }
    }
}

contract BadRecordKeeper is PDPApplication {
    PDPApplication.OperationType public badOperation;

    function setBadOperation(PDPApplication.OperationType operationType) external {
        badOperation = operationType;
    }

    function notify(
        uint256,
        uint64,
        PDPApplication.OperationType operationType,
        bytes calldata
    ) view external {
        if (operationType == badOperation) {
            revert("Failing operation");
        }
    }
}

contract RecordKeeperIntegrationTest is Test {
    PDPService pdpService;
    BadRecordKeeper badRecordKeeper;

    function setUp() public {
        pdpService = new PDPService(2);
    }

    function testRecordKeeperPropagatesErrors() public {
        BadRecordKeeper recordKeeper = new BadRecordKeeper();

        // Can't create a proof set with a bad record keeper
        recordKeeper.setBadOperation(PDPApplication.OperationType.CREATE);
        vm.expectRevert("Failing operation");
        pdpService.createProofSet(address(recordKeeper));

        recordKeeper.setBadOperation(PDPApplication.OperationType.NONE);
        pdpService.createProofSet(address(recordKeeper));

        recordKeeper.setBadOperation(PDPApplication.OperationType.ADD);
        PDPService.RootData[] memory roots = new PDPService.RootData[](1);
        roots[0] = PDPService.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        vm.expectRevert("Failing operation");
        pdpService.addRoots(0, roots);

        recordKeeper.setBadOperation(PDPApplication.OperationType.NONE);
        pdpService.addRoots(0, roots);

        recordKeeper.setBadOperation(PDPApplication.OperationType.REMOVE);
        uint256[] memory rootIds = new uint256[](1);
        rootIds[0] = 0;
        vm.expectRevert("Failing operation");
        pdpService.removeRoots(0, rootIds);
    }
}

