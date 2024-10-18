pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";
import {PDPVerifier, PDPListener} from "../src/PDPVerifier.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {MerkleProve} from "../src/Proofs.sol";
import {ProofUtil} from "./ProofUtil.sol";
import {PDPFees} from "../src/Fees.sol";
import {SimplePDPService, PDPRecordKeeper} from "../src/SimplePDPService.sol";

contract PDPVerifierProofSetCreateDeleteTest is Test {
    SimplePDPService listener;
    ListenerHelper listenerAssert;
    PDPVerifier pdpVerifier;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        uint256 challengeFinality = 2;
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinality
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        SimplePDPService listenerImpl = new SimplePDPService();
        initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifier));
        MyERC1967Proxy listenerProxy = new MyERC1967Proxy(address(listenerImpl), initializeData);
        listener = SimplePDPService(address(listenerProxy));
        listenerAssert = new ListenerHelper(address(listener));
    }
    function tearDown() public view {
        listenerAssert.assertAllEvents();
    }

    function testCreateProofSet() public {
        Cids.Cid memory zeroRoot;
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        assertEq(setId, 0, "First proof set ID should be 0");
        assertEq(pdpVerifier.getProofSetLeafCount(setId), 0, "Proof set leaf count should be 0");

        (address owner, address proposedOwner) = pdpVerifier.getProofSetOwner(setId);
        assertEq(owner, address(this), "Proof set owner should be the constructor sender");
        assertEq(proposedOwner, address(0), "Proof set proposed owner should be initialized to zero address");

        assertEq(pdpVerifier.getNextChallengeEpoch(setId), 0, "Proof set challenge epoch should be zero");
        assertEq(pdpVerifier.rootLive(setId, 0), false, "Proof set root should not be live");
        assertEq(pdpVerifier.getRootCid(setId, 0).data, zeroRoot.data, "Uninitialized root should be empty");
        assertEq(pdpVerifier.getRootLeafCount(setId, 0), 0, "Uninitialized root should have zero leaves");
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), 0, "Proof set challenge epoch should be zero");
        tearDown();
    }

    function testDeleteProofSet() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        pdpVerifier.deleteProofSet(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.DELETE, setId);
        vm.expectRevert("Proof set not live");
        pdpVerifier.getProofSetLeafCount(setId);
        tearDown();
    }

    function testOnlyOwnerCanDeleteProofSet() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        // Create a new address to act as a non-owner
        address nonOwner = address(0x1234);
        // Expect revert when non-owner tries to delete the proof set
        vm.prank(nonOwner);
        vm.expectRevert("Only the owner can delete proof sets");
        pdpVerifier.deleteProofSet(setId);

        // Now verify the owner can delete the proof set
        pdpVerifier.deleteProofSet(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.DELETE, setId);
        vm.expectRevert("Proof set not live");
        pdpVerifier.getProofSetOwner(setId);
        tearDown();
    }

    // TODO: once we have addRoots we should test deletion of a non empty proof set
    function testCannotDeleteNonExistentProofSet() public {
        vm.expectRevert("proof set id out of bounds");
        pdpVerifier.deleteProofSet(0);
        tearDown();
    }

    function testMethodsOnDeletedProofSetFails() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        pdpVerifier.deleteProofSet(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.DELETE, setId);
        vm.expectRevert("Only the owner can delete proof sets");
        pdpVerifier.deleteProofSet(setId);
        vm.expectRevert("Proof set not live");
        pdpVerifier.getProofSetOwner(setId);
        vm.expectRevert("Proof set not live");
        pdpVerifier.getProofSetLeafCount(setId);
        vm.expectRevert("Proof set not live");
        pdpVerifier.getRootCid(setId, 0);
        vm.expectRevert("Proof set not live");
        pdpVerifier.getRootLeafCount(setId, 0);
        vm.expectRevert("Proof set not live");
        pdpVerifier.getNextChallengeEpoch(setId);
        vm.expectRevert("Proof set not live");
        pdpVerifier.addRoots(setId, new PDPVerifier.RootData[](0));
        tearDown();
    }

    function testGetProofSetID() public {
        pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, 0);
        pdpVerifier.createProofSet{value: PDPFees.sybilFee()} (address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, 1);
        assertEq(2, pdpVerifier.getNextProofSetId(), "Next proof set ID should be 2");
        tearDown();
    }

    receive() external payable {}

    function testCreateProofSetFeeHandling() public {
        uint256 sybilFee = PDPFees.sybilFee();
        
        // Test 1: Fails when sending not enough for sybil fee
        vm.expectRevert("sybil fee not met");
        pdpVerifier.createProofSet{value: sybilFee - 1}(address(listener));

        // Test 2: Returns funds over the sybil fee back to the sender
        uint256 excessAmount = 1 ether;
        uint256 initialBalance = address(this).balance;
        
        uint256 setId = pdpVerifier.createProofSet{value: sybilFee + excessAmount}(address(listener));
        
        uint256 finalBalance = address(this).balance;
        uint256 refundedAmount = finalBalance - (initialBalance - sybilFee - excessAmount);
        assertEq(refundedAmount, excessAmount, "Excess amount should be refunded");

        // Additional checks to ensure the proof set was created correctly
        assertEq(pdpVerifier.getProofSetLeafCount(setId), 0, "Proof set leaf count should be 0");
        (address owner, address proposedOwner) = pdpVerifier.getProofSetOwner(setId);
        assertEq(owner, address(this), "Proof set owner should be the constructor sender");
        assertEq(proposedOwner, address(0), "Proof set proposed owner should be initialized to zero address");
    }
}

contract PDPVerifierOwnershipTest is Test {
    PDPVerifier pdpVerifier;
    SimplePDPService listener;
    address public owner;
    address public nextOwner;
    address public nonOwner;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            2
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        SimplePDPService listenerImpl = new SimplePDPService();
        initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifier));
        MyERC1967Proxy listenerProxy = new MyERC1967Proxy(address(listenerImpl), initializeData);
        listener = SimplePDPService(address(listenerProxy));

        owner = address(this);
        nextOwner = address(0x1234);
        nonOwner = address(0xffff);
    }

    function testOwnershipTransfer() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        pdpVerifier.proposeProofSetOwner(setId, nextOwner);
        (address ownerStart, address proposedOwnerStart) = pdpVerifier.getProofSetOwner(setId);
        assertEq(ownerStart, owner, "Proof set owner should be the constructor sender");
        assertEq(proposedOwnerStart, nextOwner, "Proof set proposed owner should make the one proposed");
        vm.prank(nextOwner);
        pdpVerifier.claimProofSetOwnership(setId);
        (address ownerEnd, address proposedOwnerEnd) = pdpVerifier.getProofSetOwner(setId);
        assertEq(ownerEnd, nextOwner, "Proof set owner should be the next owner");
        assertEq(proposedOwnerEnd, address(0), "Proof set proposed owner should be zero address");
    }

    function testOwnershipProposalReset() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        pdpVerifier.proposeProofSetOwner(setId, nextOwner);
        pdpVerifier.proposeProofSetOwner(setId, owner);
        (address ownerEnd, address proposedOwnerEnd) = pdpVerifier.getProofSetOwner(setId);
        assertEq(ownerEnd, owner, "Proof set owner should be the constructor sender");
        assertEq(proposedOwnerEnd, address(0), "Proof set proposed owner should be zero address");
    }

    function testOwnershipPermissionsRequired() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        vm.prank(nonOwner);
        vm.expectRevert("Only the current owner can propose a new owner");
        pdpVerifier.proposeProofSetOwner(setId, nextOwner);

        // Now send proposal from actual owner
        pdpVerifier.proposeProofSetOwner(setId, nextOwner);

        // Proposed owner has no extra permissions
        vm.prank(nextOwner);
        vm.expectRevert("Only the current owner can propose a new owner");
        pdpVerifier.proposeProofSetOwner(setId, nonOwner);

        vm.prank(nonOwner);
        vm.expectRevert("Only the proposed owner can claim ownership");
        pdpVerifier.claimProofSetOwnership(setId);
    }

    function testScheduleRemoveRootsOnlyOwner() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test"));
        PDPVerifier.RootData[] memory rootDataArray = new PDPVerifier.RootData[](1);
        rootDataArray[0] = PDPVerifier.RootData(testCid, 100 * pdpVerifier.LEAF_SIZE());
        pdpVerifier.addRoots(setId, rootDataArray);

        uint256[] memory rootIdsToRemove = new uint256[](1);
        rootIdsToRemove[0] = 0;

        vm.prank(nonOwner);
        vm.expectRevert("Only the owner can schedule removal of roots");
        pdpVerifier.scheduleRemovals(setId, rootIdsToRemove);
    }
}

contract PDPVerifierProofSetMutateTest is Test {
    uint256 constant challengeFinalityDelay = 2;

    PDPVerifier pdpVerifier;
    SimplePDPService listener;
    ListenerHelper listenerAssert;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        SimplePDPService listenerImpl = new SimplePDPService();
        initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifier));
        MyERC1967Proxy listenerProxy = new MyERC1967Proxy(address(listenerImpl), initializeData);
        listener = SimplePDPService(address(listenerProxy));
        listenerAssert = new ListenerHelper(address(listener));
    }

    function tearDown() public view {
        listenerAssert.assertAllEvents();
    }

    function testAddRoot() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](1);
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 64);
        uint256 rootId = pdpVerifier.addRoots(setId, roots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.ADD, setId);
        // flush add
        pdpVerifier.nextProvingPeriod(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        uint256 leafCount = roots[0].rawSize / 32;
        assertEq(pdpVerifier.getProofSetLeafCount(setId), leafCount);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);
        assertEq(pdpVerifier.getChallengeRange(setId), leafCount);

        assertTrue(pdpVerifier.rootLive(setId, rootId));
        assertEq(pdpVerifier.getRootCid(setId, rootId).data, roots[0].root.data);
        assertEq(pdpVerifier.getRootLeafCount(setId, rootId), leafCount);

        assertEq(pdpVerifier.getNextRootId(setId), 1);
        tearDown();
    }

    function testAddMultipleRoots() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](2);
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test1")), 64);
        roots[1] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test2")), 128);
        uint256 firstId = pdpVerifier.addRoots(setId, roots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.ADD, setId);
        assertEq(firstId, 0);
        // flush add
        pdpVerifier.nextProvingPeriod(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        uint256 expectedLeafCount = roots[0].rawSize / 32 + roots[1].rawSize / 32;
        assertEq(pdpVerifier.getProofSetLeafCount(setId), expectedLeafCount);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);

        assertTrue(pdpVerifier.rootLive(setId, firstId));
        assertTrue(pdpVerifier.rootLive(setId, firstId + 1));
        assertEq(pdpVerifier.getRootCid(setId, firstId).data, roots[0].root.data);
        assertEq(pdpVerifier.getRootCid(setId, firstId + 1).data, roots[1].root.data);

        assertEq(pdpVerifier.getRootLeafCount(setId, firstId), roots[0].rawSize / 32);
        assertEq(pdpVerifier.getRootLeafCount(setId, firstId + 1), roots[1].rawSize / 32);
        assertEq(pdpVerifier.getNextRootId(setId), 2);
        tearDown();
    }

    function expectIndexedError(uint256 index, string memory expectedMessage) internal {
        vm.expectRevert(abi.encodeWithSelector(PDPVerifier.IndexedError.selector, index, expectedMessage));
    }

    function testAddBadRoot() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](1);

        // Fail when root size is not a multiple of 32
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 63);
        expectIndexedError(0, "Size must be a multiple of 32");
        pdpVerifier.addRoots(setId, roots);

        // Fail when root size is zero
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 0);
        expectIndexedError(0, "Size must be greater than 0");
        pdpVerifier.addRoots(setId, roots);

        // Fail when root size is too large
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), pdpVerifier.MAX_ROOT_SIZE() + 32);
        expectIndexedError(0, "Root size must be less than 2^50");
        pdpVerifier.addRoots(setId, roots);

        // Fail when not adding any roots;
        PDPVerifier.RootData[] memory emptyRoots = new PDPVerifier.RootData[](0);
        vm.expectRevert("Must add at least one root");
        pdpVerifier.addRoots(setId, emptyRoots);

        // Fail when proof set is no longer live
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        pdpVerifier.deleteProofSet(setId);
        vm.expectRevert("Proof set not live");
        pdpVerifier.addRoots(setId, roots);
    }

    function testAddBadRootsBatched() public {
        // Add one bad root, message fails on bad index
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](4);
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        roots[1] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        roots[2] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        roots[3] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 31);

        expectIndexedError(3, "Size must be a multiple of 32");
        pdpVerifier.addRoots(setId, roots);

        // Add multiple bad roots, message fails on first bad index
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 63);
        expectIndexedError(0, "Size must be a multiple of 32");
        pdpVerifier.addRoots(setId, roots);
    }

    function testRemoveRoot() public {
        // Add one root
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](1);
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addRoots(setId, roots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.ADD, setId);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);

        // Remove root
        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 0;
        pdpVerifier.scheduleRemovals(setId, toRemove);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, setId);

        pdpVerifier.nextProvingPeriod(setId); // flush
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        assertEq(pdpVerifier.getNextChallengeEpoch(setId), 0);
        assertEq(pdpVerifier.rootLive(setId, 0), false);
        assertEq(pdpVerifier.getNextRootId(setId), 1);
        assertEq(pdpVerifier.getProofSetLeafCount(setId), 0);
        bytes memory emptyCidData = new bytes(0);
        assertEq(pdpVerifier.getRootCid(setId, 0).data, emptyCidData);
        assertEq(pdpVerifier.getRootLeafCount(setId, 0), 0);
    }

    function testRemoveRootBatch() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](3);
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test1")), 64);
        roots[1] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test2")), 64);
        roots[2] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addRoots(setId, roots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.ADD, setId);
        uint256[] memory toRemove = new uint256[](2);
        toRemove[0] = 0;
        toRemove[1] = 2;
        pdpVerifier.scheduleRemovals(setId, toRemove);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, setId);
        pdpVerifier.nextProvingPeriod(setId); // flush
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        assertEq(pdpVerifier.rootLive(setId, 0), false);
        assertEq(pdpVerifier.rootLive(setId, 1), true);
        assertEq(pdpVerifier.rootLive(setId, 2), false);

        assertEq(pdpVerifier.getNextRootId(setId), 3);
        assertEq(pdpVerifier.getProofSetLeafCount(setId), 64/32);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);

        bytes memory emptyCidData = new bytes(0);
        assertEq(pdpVerifier.getRootCid(setId, 0).data, emptyCidData);
        assertEq(pdpVerifier.getRootCid(setId, 1).data, roots[1].root.data);
        assertEq(pdpVerifier.getRootCid(setId, 2).data, emptyCidData);

        assertEq(pdpVerifier.getRootLeafCount(setId, 0), 0);
        assertEq(pdpVerifier.getRootLeafCount(setId, 1), 64/32);
        assertEq(pdpVerifier.getRootLeafCount(setId, 2), 0);

    }

    function testRemoveFutureRoots() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](1);
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 64);
        pdpVerifier.addRoots(setId, roots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.ADD, setId);
        assertEq(true, pdpVerifier.rootLive(setId, 0));
        assertEq(false, pdpVerifier.rootLive(setId, 1));
        uint256[] memory toRemove = new uint256[](2);

        // Scheduling an un-added root for removal should fail
        toRemove[0] = 0; // current root
        toRemove[1] = 1; // future root
        vm.expectRevert("Can only schedule removal of existing roots");
        pdpVerifier.scheduleRemovals(setId, toRemove);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, setId);
        // Actual removal does not fail
        pdpVerifier.nextProvingPeriod(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        // Scheduling both unchallengeable and challengeable roots for removal succeeds
        // scheduling duplicate ids in both cases succeeds
        uint256[] memory toRemove2 = new uint256[](4);
        pdpVerifier.addRoots(setId, roots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.ADD, setId);
        toRemove2[0] = 0; // current challengeable root
        toRemove2[1] = 1; // current unchallengeable root
        toRemove2[2] = 0; // duplicate challengeable
        toRemove2[3] = 1; // duplicate unchallengeable
        // state exists for both roots
        assertEq(true, pdpVerifier.rootLive(setId, 0));
        assertEq(true, pdpVerifier.rootLive(setId, 1));
        // only root 0 is challengeable
        assertEq(true, pdpVerifier.rootChallengable(setId, 0));
        assertEq(false, pdpVerifier.rootChallengable(setId, 1));
        pdpVerifier.scheduleRemovals(setId, toRemove2);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, setId);
        pdpVerifier.nextProvingPeriod(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        assertEq(false, pdpVerifier.rootLive(setId, 0));
        assertEq(false, pdpVerifier.rootLive(setId, 1));
    }
}

contract ProofBuilderHelper is Test {
    // Builds a proof of posession for a proof set
    function buildProofs(PDPVerifier pdpVerifier, uint256 setId, uint challengeCount, bytes32[][][] memory trees, uint[] memory leafCounts) internal view returns (PDPVerifier.Proof[] memory) {
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        uint256 seed = challengeEpoch; // Seed is (temporarily) the challenge epoch
        uint totalLeafCount = 0;
        for (uint i = 0; i < leafCounts.length; ++i) {
            totalLeafCount += leafCounts[i];
        }

        PDPVerifier.Proof[] memory proofs = new PDPVerifier.Proof[](challengeCount);
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
            proofs[challengeIdx] = PDPVerifier.Proof(tree[tree.length - 1][treeOffset], path);

            // console.log("Leaf", vm.toString(proofs[0].leaf));
            // console.log("Proof");
            // for (uint j = 0; j < proofs[0].proof.length; j++) {
            //     console.log(vm.toString(j), vm.toString(proofs[0].proof[j]));
            // }
        }

        return proofs;
    }
}

contract PDPVerifierProofTest is Test, ProofBuilderHelper {
    uint256 constant challengeFinalityDelay = 2;
    string constant cidPrefix = "CID";
    PDPVerifier pdpVerifier;
    SimplePDPService listener;
    ListenerHelper listenerAssert;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        SimplePDPService listenerImpl = new SimplePDPService();
        initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifier));
        MyERC1967Proxy listenerProxy = new MyERC1967Proxy(address(listenerImpl), initializeData);
        listener = SimplePDPService(address(listenerProxy));
        listenerAssert = new ListenerHelper(address(listener));
    }

    function tearDown() public view {
        listenerAssert.assertAllEvents();
    }

    function testProveSingleRoot() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with  multiple challenges to single tree.
        uint challengeCount = 3;
        PDPVerifier.Proof[] memory proofs = buildProofsForSingleton(setId, challengeCount, tree, leafCount);

        // Submit proof.
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofs.length)}(setId, proofs);

        // Verify the next challenge is in a subsequent epoch.
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.PROVE_POSSESSION, setId);
        // Next challenge unchanged by prove
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), challengeEpoch);

        // Verify the next challenge is in a subsequent epoch after nextProvingPeriod
        pdpVerifier.nextProvingPeriod(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay);
        tearDown();
    }

    receive() external payable {}

    function testProveWithDifferentFeeAmounts() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(leafCount);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with multiple challenges to single tree.
        uint challengeCount = 3;
        PDPVerifier.Proof[] memory proofs = buildProofsForSingleton(setId, challengeCount, tree, leafCount);

        // Calculate the correct proof fee
        uint256 correctProofFee = PDPFees.proofFee(challengeCount);

        // Test 1: Sending less than the required fee
        uint256 insufficientFee = correctProofFee - 1;
        vm.expectRevert("Incorrect fee amount");
        pdpVerifier.provePossession{value: insufficientFee}(setId, proofs);

        // Test 2: Sending more than the required fee
        uint256 excessFee = correctProofFee + 1 ether;
        uint256 initialBalance = address(this).balance;
        
        pdpVerifier.provePossession{value: excessFee}(setId, proofs);
        
        uint256 finalBalance = address(this).balance;
        uint256 actualFeeSpent = initialBalance - finalBalance;
        assertEq(actualFeeSpent, correctProofFee, "Only the correct fee should be spent");

        // Verify that the proof was accepted
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.PROVE_POSSESSION, setId);
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), challengeEpoch, "Next challenge epoch should remain unchanged after prove");

        tearDown();
    }

    function testLateProofAccepted() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(leafCount);

        // Advance chain short of challenge epoch
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch + 100);

        // Build a proof.
        PDPVerifier.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof.
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofs.length)}(setId, proofs);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.PROVE_POSSESSION, setId);
        tearDown();
    }

    function testEarlyProofRejected() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(leafCount);

        // Advance chain short of challenge epoch
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch - 1);

        // Build a proof.
        PDPVerifier.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof.
        vm.expectRevert();
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofs.length)}(setId, proofs);
        tearDown();
    }

    function testEmptyProofRejected() public {
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        PDPVerifier.Proof[] memory emptyProof = new PDPVerifier.Proof[](0);

        // Rejected with no roots
        vm.expectRevert();
        pdpVerifier.provePossession{value: PDPFees.proofFee(0)}(setId, emptyProof);

        addOneRoot(setId, 10);

        // Rejected with a root
        vm.expectRevert();
        pdpVerifier.provePossession{value: PDPFees.proofFee(0)}(setId, emptyProof);
        tearDown();
    }

    function testBadChallengeRejected() public {
        uint leafCount = 10;
        (uint256 setId, bytes32[][] memory tree) = makeProofSetWithOneRoot(leafCount);

        // Make a proof that's good for this challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        PDPVerifier.Proof[] memory proofs = buildProofsForSingleton(setId, 3, tree, leafCount);

        // Submit proof successfully, advancing the proof set to a new challenge epoch.
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofs.length)}(setId, proofs);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.PROVE_POSSESSION, setId);
        pdpVerifier.nextProvingPeriod(setId); // resample
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        uint nextChallengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        assertNotEq(nextChallengeEpoch, challengeEpoch);
        vm.roll(nextChallengeEpoch);

        // The proof for the old challenge epoch should no longer be valid.
        vm.expectRevert();
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofs.length)}(setId, proofs);
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
        // Add another root before submitting the proof.
        uint256 newRootId;
        (trees[1], newRootId) = addOneRoot(setId, leafCounts[1]);

        // Make a proof that's good for the single root.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);
        PDPVerifier.Proof[] memory proofsOneRoot = buildProofsForSingleton(setId, 3, trees[0], leafCounts[0]);

        // The proof for one root should be invalid against the set with two.
        vm.expectRevert();
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofsOneRoot.length)}(setId, proofsOneRoot);

        // Remove a root and resample
        uint256[] memory removeRoots = new uint256[](1);
        removeRoots[0] = newRootId;
        pdpVerifier.scheduleRemovals(setId, removeRoots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, setId);
        // flush removes
        pdpVerifier.nextProvingPeriod(setId);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);

        // Make a new proof that is valid with two roots
        vm.roll(pdpVerifier.getNextChallengeEpoch(setId));
        PDPVerifier.Proof[] memory proofsTwoRoots = buildProofs(pdpVerifier, setId, 1, trees, leafCounts);

        // A proof for two roots should be invalid against the set with one.
        proofsTwoRoots = buildProofs(pdpVerifier, setId, 1, trees, leafCounts); // regen as removal forced resampling challenge seed
        vm.expectRevert();
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofsTwoRoots.length)}(setId, proofsTwoRoots);

        // But the single root proof is now good again.
        proofsOneRoot = buildProofsForSingleton(setId, 1, trees[0], leafCounts[0]); // regen as removal forced resampling challenge seed
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofsOneRoot.length)}(setId, proofsOneRoot);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.PROVE_POSSESSION, setId);
        tearDown();
    }

    function testProveManyRoots() public {
        uint[] memory leafCounts = new uint[](3);
        // Pick a distinct size for each tree (up to some small maximum size).
        for (uint i = 0; i < leafCounts.length; i++) {
            leafCounts[i] = uint256(sha256(abi.encode(i))) % 64;
        }

        (uint256 setId, bytes32[][][] memory trees) = makeProofSetWithRoots(leafCounts);

        // Advance chain until challenge epoch.
        uint256 challengeEpoch = pdpVerifier.getNextChallengeEpoch(setId);
        vm.roll(challengeEpoch);

        // Build a proof with multiple challenges to span the roots.
        uint challengeCount = 11;
        PDPVerifier.Proof[] memory proofs = buildProofs(pdpVerifier, setId, challengeCount, trees, leafCounts);
        // Submit proof.
        pdpVerifier.provePossession{value: PDPFees.proofFee(proofs.length)}(setId, proofs);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.PROVE_POSSESSION, setId);
        tearDown();
    }


    ///// Helpers /////

    // Initializes a new proof set, generates trees of specified sizes, and adds roots to the set.
    function makeProofSetWithRoots(uint[] memory leafCounts) internal returns (uint256, bytes32[][][]memory) {
        // Create trees and their roots.
        bytes32[][][] memory trees = new bytes32[][][](leafCounts.length);
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](leafCounts.length);
        for (uint i = 0; i < leafCounts.length; i++) {
            // Generate a uniquely-sized tree for each root (up to some small maximum size).
            trees[i] = ProofUtil.makeTree(leafCounts[i]);
            roots[i] = makeRoot(trees[i], leafCounts[i]);
        }

        // Create new proof set and add roots.
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.CREATE, setId);
        pdpVerifier.addRoots(setId, roots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.ADD, setId);
        pdpVerifier.nextProvingPeriod(setId); // flush adds
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);
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
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](1);
        roots[0] = makeRoot(tree, leafCount);
        uint256 rootId = pdpVerifier.addRoots(setId, roots);
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.ADD, setId);
        pdpVerifier.nextProvingPeriod(setId); // flush adds
        listenerAssert.expectEvent(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, setId);
        return (tree, rootId);
    }

    // Constructs a RootData structure for a Merkle tree.
    function makeRoot(bytes32[][] memory tree, uint leafCount) internal pure returns (PDPVerifier.RootData memory) {
        return PDPVerifier.RootData(Cids.cidFromDigest(bytes(cidPrefix), tree[0][0]), leafCount * 32);
    }

    // Builds a proof of posesesion for a proof set with a single root.
    function buildProofsForSingleton(uint256 setId, uint challengeCount, bytes32[][] memory tree, uint leafCount) internal view returns (PDPVerifier.Proof[] memory) {
        bytes32[][][] memory trees = new bytes32[][][](1);
        trees[0] = tree;
        uint[] memory leafCounts = new uint[](1);
        leafCounts[0] = leafCount;
        PDPVerifier.Proof[] memory proofs = buildProofs(pdpVerifier, setId, challengeCount, trees, leafCounts);
        return proofs;
    }
}

contract SumTreeInternalTestPDPVerifier is PDPVerifier {
    constructor() {
    }
    function getTestHeightFromIndex(uint256 index) public pure returns (uint256) {
        return heightFromIndex(index);
    }

    function getSumTreeCounts(uint256 setId, uint256 rootId) public view returns (uint256) {
        return sumTreeCounts[setId][rootId];
    }
}

contract SumTreeHeightTest is Test {
    SumTreeInternalTestPDPVerifier pdpVerifier;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new SumTreeInternalTestPDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            2
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = SumTreeInternalTestPDPVerifier(address(proxy));
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
            assertEq(uint256(oeisA001511[i]), pdpVerifier.getTestHeightFromIndex(i) + 1, "Heights from index 0 to 104 should match OEIS A001511");
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/PDPVerifier.sol";

contract SumTreeAddTest is Test {
    SumTreeInternalTestPDPVerifier pdpVerifier;
    SimplePDPService listener;
    uint256 testSetId;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new SumTreeInternalTestPDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            100
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = SumTreeInternalTestPDPVerifier(address(proxy));
        SimplePDPService listenerImpl = new SimplePDPService();
        initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifier));
        MyERC1967Proxy listenerProxy = new MyERC1967Proxy(address(listenerImpl), initializeData);
        listener = SimplePDPService(address(listenerProxy));       
        testSetId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));
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

        PDPVerifier.RootData[] memory rootDataArray = new PDPVerifier.RootData[](8);

        for (uint256 i = 0; i < counts.length; i++) {
            Cids.Cid memory testCid = Cids.Cid(abi.encodePacked("test", i));
            rootDataArray[i] = PDPVerifier.RootData(testCid, counts[i] * pdpVerifier.LEAF_SIZE());
        }
        pdpVerifier.addRoots(testSetId, rootDataArray);
        assertEq(pdpVerifier.getProofSetLeafCount(testSetId), 87, "Incorrect final proof set leaf count");
        assertEq(pdpVerifier.getNextRootId(testSetId), 8, "Incorrect next root ID");
        assertEq(pdpVerifier.getSumTreeCounts(testSetId, 7), 87, "Incorrect sum tree count");
        assertEq(pdpVerifier.getRootLeafCount(testSetId, 7), 34, "Incorrect root leaf count");
        Cids.Cid memory expectedCid = Cids.Cid(abi.encodePacked("test", uint256(3)));
        Cids.Cid memory actualCid = pdpVerifier.getRootCid(testSetId, 3);
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
            PDPVerifier.RootData[] memory rootDataArray = new PDPVerifier.RootData[](1);
            rootDataArray[0] = PDPVerifier.RootData(testCid, counts[i] * pdpVerifier.LEAF_SIZE());
            pdpVerifier.addRoots(testSetId, rootDataArray);
            // Assert the root was added correctly
            assertEq(pdpVerifier.getRootCid(testSetId, i).data, testCid.data, "Root not added correctly");
        }

        // Delete some
        // Remove roots in batch
        pdpVerifier.scheduleRemovals(testSetId, rootIdsToRemove);
        // flush adds and removals
        pdpVerifier.nextProvingPeriod(testSetId);
        for (uint256 i = 0; i < rootIdsToRemove.length; i++) {
            bytes memory zeroBytes;
            assertEq(pdpVerifier.getRootCid(testSetId, rootIdsToRemove[i]).data, zeroBytes);
            assertEq(pdpVerifier.getRootLeafCount(testSetId, rootIdsToRemove[i]), 0, "Root size should be 0");
        }
    }

    function testSumTree() public {
        (uint256[] memory counts, uint256[] memory expectedSumTreeCounts) = setUpTestingArray();
        // Assert that the sum tree count is correct
        for (uint256 i = 0; i < counts.length; i++) {
            assertEq(pdpVerifier.getSumTreeCounts(testSetId, i), expectedSumTreeCounts[i], "Incorrect sum tree size");
        }

        // Assert final proof set leaf count
        assertEq(pdpVerifier.getProofSetLeafCount(testSetId), 820, "Incorrect final proof set leaf count");
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
        pdpVerifier.findRootIds(testSetId, outOfBounds);

        vm.expectRevert("Leaf index out of bounds");
        outOfBounds[0] = 1000;
        pdpVerifier.findRootIds(testSetId, outOfBounds);
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
        PDPVerifier.RootIdAndOffset[] memory result = pdpVerifier.findRootIds(setId, searchIndices);
        if (result[0].rootId != expectRootId) {
            revert TestingFindError(expectRootId, result[0].rootId, "unexpected root");
        }
        if (result[0].offset != expectOffset) {
            revert TestingFindError(expectOffset, result[0].offset, "unexpected offset");
        }
    }

    // The batched version of assertFindRootAndOffset
    function assertFindRootsAndOffsets(uint256 setId, uint256[] memory searchIndices, uint256[] memory expectRootIds, uint256[] memory expectOffsets) internal view {
        PDPVerifier.RootIdAndOffset[] memory result = pdpVerifier.findRootIds(setId, searchIndices);
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
            PDPVerifier.RootData[] memory rootDataArray = new PDPVerifier.RootData[](1);
            rootDataArray[0] = PDPVerifier.RootData(testCid, sizes[i] * pdpVerifier.LEAF_SIZE());
            pdpVerifier.addRoots(testSetId, rootDataArray);
        }
        pdpVerifier.scheduleRemovals(testSetId, rootIdsToRemove);
        pdpVerifier.nextProvingPeriod(testSetId); //flush removals

        assertFindRootAndOffset(testSetId, 0, 3, 0);
        assertFindRootAndOffset(testSetId, 1, 4, 0);
    }
}

contract ListenerHelper is Test {
    address pdpVerifier;
    mapping(uint256 => bool) public seenSetIds;
    uint256[] public setIds;
    mapping(uint256 => PDPRecordKeeper.OperationType[]) public expectedRecords;

    constructor(address _pdpVerifier) {
        pdpVerifier = _pdpVerifier;
    }

    function expectEvent(PDPRecordKeeper.OperationType operationType, uint256 setId) public {
        if (!seenSetIds[setId]) {
            setIds.push(setId);
            seenSetIds[setId] = true;
        }

        expectedRecords[setId].push(operationType);
    }

    function assertAllEvents() public view {
        for (uint256 i = 0; i < setIds.length; i++) {
            assertProofSetEvents(setIds[i]);
        }
    }

    function assertProofSetEvents(uint256 setId) public view {
        SimplePDPService.EventRecord[] memory records = SimplePDPService(pdpVerifier).listEvents(setId);
        assertEq(expectedRecords[setId].length, records.length, "Incorrect number of records");
        for (uint256 i = 0; i < records.length; i++) {
            assertEq(records[i].proofSetId, setId, "Incorrect proof set ID");
            assertEq(uint(records[i].operationType), uint(expectedRecords[setId][i]), "Incorrect operation type");
            assertRecordDataFormat(records[i].operationType, records[i].extraData);
        }
    }

    // Assert the data format for each operation type
    // This will need to be updated for all changes to the data format externalized to the listener
    function assertRecordDataFormat(PDPRecordKeeper.OperationType operationType, bytes memory extraData) internal pure {
        if (operationType == PDPRecordKeeper.OperationType.CREATE) {
            abi.decode(extraData, (address));
        } else if (operationType == PDPRecordKeeper.OperationType.ADD) {
            abi.decode(extraData, (uint256,PDPVerifier.RootData[]));
        } else if (operationType == PDPRecordKeeper.OperationType.REMOVE_SCHEDULED) {
            (uint256[] memory rootIds) = abi.decode(extraData, (uint256[]));
            require(rootIds.length > 0, "REMOVE_SCHEDULED: rootIds should not be empty");
        } else if (operationType == PDPRecordKeeper.OperationType.PROVE_POSSESSION) {
            abi.decode(extraData, (uint256, uint256));
        } else if (operationType == PDPRecordKeeper.OperationType.DELETE) {
            abi.decode(extraData, (uint256));
        } else if (operationType == PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD) {
            abi.decode(extraData, (uint256));
        } else {
            revert("Unknown operation type");
        }
    }
}

contract BadListener is PDPListener {
    PDPRecordKeeper.OperationType public badOperation;

    function setBadOperation(PDPRecordKeeper.OperationType operationType) external {
        badOperation = operationType;
    }

    function proofSetCreated(uint256 proofSetId, address creator) external view {
        receiveProofSetEvent(proofSetId, PDPRecordKeeper.OperationType.CREATE, abi.encode(creator));
    }

    function proofSetDeleted(uint256 proofSetId, uint256 deletedLeafCount) external view {
        receiveProofSetEvent(proofSetId, PDPRecordKeeper.OperationType.DELETE, abi.encode(deletedLeafCount));
    }

    function rootsAdded(uint256 proofSetId, uint256 firstAdded, PDPVerifier.RootData[] calldata rootData) external view {
        receiveProofSetEvent(proofSetId, PDPRecordKeeper.OperationType.ADD, abi.encode(firstAdded, rootData));
    }

    function rootsScheduledRemove(uint256 proofSetId, uint256[] calldata rootIds) external view {
        receiveProofSetEvent(proofSetId, PDPRecordKeeper.OperationType.REMOVE_SCHEDULED, abi.encode(rootIds));
    }

    function posessionProven(uint256 proofSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount) external view {
        receiveProofSetEvent(proofSetId, PDPRecordKeeper.OperationType.PROVE_POSSESSION, abi.encode(challengedLeafCount, seed, challengeCount));
    }

    function nextProvingPeriod(uint256 proofSetId, uint256 leafCount) external view {
        receiveProofSetEvent(proofSetId, PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD, abi.encode(leafCount));
    }

    function receiveProofSetEvent(
        uint256,
        PDPRecordKeeper.OperationType operationType,
        bytes memory
    ) view internal {
        if (operationType == badOperation) {
            revert("Failing operation");
        }
    }
}

contract PDPListenerIntegrationTest is Test {
    PDPVerifier pdpVerifier;
    BadListener badListener;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            2
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        badListener = new BadListener();
    }

    function testListenerPropagatesErrors() public {

        // Can't create a proof set with a bad listener
        badListener.setBadOperation(PDPRecordKeeper.OperationType.CREATE);
        vm.expectRevert("Failing operation");
        pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(badListener));

        badListener.setBadOperation(PDPRecordKeeper.OperationType.NONE);
        pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(badListener));

        badListener.setBadOperation(PDPRecordKeeper.OperationType.ADD);
        PDPVerifier.RootData[] memory roots = new PDPVerifier.RootData[](1);
        roots[0] = PDPVerifier.RootData(Cids.Cid(abi.encodePacked("test")), 32);
        vm.expectRevert("Failing operation");
        pdpVerifier.addRoots(0, roots);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.NONE);
        pdpVerifier.addRoots(0, roots);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.REMOVE_SCHEDULED);
        uint256[] memory rootIds = new uint256[](1);
        rootIds[0] = 0;
        vm.expectRevert("Failing operation");
        pdpVerifier.scheduleRemovals(0, rootIds);

        badListener.setBadOperation(PDPRecordKeeper.OperationType.NEXT_PROVING_PERIOD);
        vm.expectRevert("Failing operation");
        pdpVerifier.nextProvingPeriod(0);
    }
}

contract PDPVerifierE2ETest is Test, ProofBuilderHelper {
    PDPVerifier pdpVerifier;
    SimplePDPService listener;
    uint256 constant challengeFinalityDelay = 2;

    function setUp() public {
        PDPVerifier pdpVerifierImpl = new PDPVerifier();
        bytes memory initializeData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            challengeFinalityDelay
        );
        MyERC1967Proxy proxy = new MyERC1967Proxy(address(pdpVerifierImpl), initializeData);
        pdpVerifier = PDPVerifier(address(proxy));
        SimplePDPService listenerImpl = new SimplePDPService();
        initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifier));
        MyERC1967Proxy listenerProxy = new MyERC1967Proxy(address(listenerImpl), initializeData);
        listener = SimplePDPService(address(listenerProxy));
    }

    function testCompleteProvingPeriodE2E() public {
        // Step 1: Create a proof set
        uint256 setId = pdpVerifier.createProofSet{value: PDPFees.sybilFee()}(address(listener));

        // Step 2: Add data `A` in scope for the first proving period
        // Note that the data in the first addRoots call is added to the first proving period
        uint256[] memory leafCountsA = new uint256[](2);
        leafCountsA[0] = 2;
        leafCountsA[1] = 3;
        bytes32[][][] memory treesA = new bytes32[][][](2);
        for (uint256 i = 0; i < leafCountsA.length; i++) {
            treesA[i] = ProofUtil.makeTree(leafCountsA[i]);
        }

        PDPVerifier.RootData[] memory rootsPP1 = new PDPVerifier.RootData[](2);
        rootsPP1[0] = PDPVerifier.RootData(Cids.cidFromDigest("test1", treesA[0][0][0]), leafCountsA[0] * 32);
        rootsPP1[1] = PDPVerifier.RootData(Cids.cidFromDigest("test2", treesA[1][0][0]), leafCountsA[1] * 32);
        pdpVerifier.addRoots(setId, rootsPP1);

        uint256 challengeRangePP1 = pdpVerifier.getChallengeRange(setId);
        assertEq(challengeRangePP1, pdpVerifier.getProofSetLeafCount(setId), "Last challenged leaf should be total leaf count - 1");

        // Step 3: Now that first challenge is set for sampling add more data `B` only in scope for the second proving period
        uint256[] memory leafCountsB = new uint256[](2);
        leafCountsB[0] = 4;
        leafCountsB[1] = 5;
        bytes32[][][] memory treesB = new bytes32[][][](2);
        for (uint256 i = 0; i < leafCountsB.length; i++) {
            treesB[i] = ProofUtil.makeTree(leafCountsB[i]);
        }

        PDPVerifier.RootData[] memory rootsPP2 = new PDPVerifier.RootData[](2);
        rootsPP2[0] = PDPVerifier.RootData(Cids.cidFromDigest("test1", treesB[0][0][0]), leafCountsB[0] * 32);
        rootsPP2[1] = PDPVerifier.RootData(Cids.cidFromDigest("test2", treesB[1][0][0]), leafCountsB[1]* 32);
        pdpVerifier.addRoots(setId, rootsPP2);

        assertEq(pdpVerifier.getRootLeafCount(setId, 0), leafCountsA[0], "sanity check: First root leaf count should be correct");
        assertEq(pdpVerifier.getRootLeafCount(setId, 1), leafCountsA[1], "Second root leaf count should be correct");
        assertEq(pdpVerifier.getRootLeafCount(setId, 2), leafCountsB[0], "Third root leaf count should be correct");
        assertEq(pdpVerifier.getRootLeafCount(setId, 3), leafCountsB[1], "Fourth root leaf count should be correct");

        // CHECK: last challenged leaf doesn't move
        assertEq(pdpVerifier.getChallengeRange(setId), challengeRangePP1, "Last challenged leaf should not move");
        assertEq(pdpVerifier.getProofSetLeafCount(setId), leafCountsA[0] + leafCountsA[1] + leafCountsB[0] + leafCountsB[1], "Leaf count should only include non-removed roots");


        // Step 5: schedule removal of first + second proving period data
        uint256[] memory rootsToRemove = new uint256[](2);

        rootsToRemove[0] = 1; // Remove the second root from first proving period
        rootsToRemove[1] = 3; // Remove the second root from second proving period
        pdpVerifier.scheduleRemovals(setId, rootsToRemove);
        assertEq(pdpVerifier.getScheduledRemovals(setId), rootsToRemove, "Scheduled removals should match rootsToRemove");

        // Step 7: complete proving period 1.
        // Advance chain until challenge epoch.
        vm.roll(pdpVerifier.getNextChallengeEpoch(setId));
        // Prepare proofs.
        uint256 challengeCount = 5;
        // Proving trees for PP1 are just treesA
        PDPVerifier.Proof[] memory proofsPP1 = buildProofs(pdpVerifier, setId, challengeCount, treesA, leafCountsA);

        pdpVerifier.provePossession{value: PDPFees.proofFee(proofsPP1.length)}(setId, proofsPP1);
        pdpVerifier.nextProvingPeriod(setId);
        // CHECK: leaf counts
        assertEq(pdpVerifier.getRootLeafCount(setId, 0), leafCountsA[0], "First root leaf count should be the set leaf count");
        assertEq(pdpVerifier.getRootLeafCount(setId, 1), 0, "Second root leaf count should be zeroed after removal");
        assertEq(pdpVerifier.getRootLeafCount(setId, 2), leafCountsB[0], "Third root leaf count should be the set leaf count");
        assertEq(pdpVerifier.getRootLeafCount(setId, 3), 0, "Fourth root leaf count should be zeroed after removal");
        assertEq(pdpVerifier.getProofSetLeafCount(setId), leafCountsA[0] + leafCountsB[0], "Leaf count should == size of non-removed roots");
        assertEq(pdpVerifier.getChallengeRange(setId), leafCountsA[0] + leafCountsB[0], "Last challenged leaf should be total leaf count");

        // CHECK: scheduled removals are processed
        assertEq(pdpVerifier.getScheduledRemovals(setId), new uint256[](0), "Scheduled removals should be processed");

        // CHECK: the next challenge epoch has been updated
        assertEq(pdpVerifier.getNextChallengeEpoch(setId), block.number + challengeFinalityDelay, "Next challenge epoch should be updated");
    }
}
