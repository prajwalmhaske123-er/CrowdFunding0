// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contract/CrowdFunding.sol";

/// @title CrowdFundingTest — Comprehensive test suite for the CrowdFunding contract.
/// @notice Covers happy paths, revert/failure cases, edge cases, and security scenarios.
contract CrowdFundingTest is Test {
    CrowdFunding public crowdFunding;

    address public creator;
    address public backer1;
    address public backer2;
    address public backer3;
    address public stranger;

    uint256 public constant GOAL = 10 ether;
    uint256 public constant DURATION = 7 days;
    bytes32 public constant IPFS_CID = keccak256("QmTestCID12345");

    // ──────────────────────────────────────────────
    //  Events (re-declared for expectEmit)
    // ──────────────────────────────────────────────
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 goalWei,
        uint256 deadlineTimestamp
    );
    event Contributed(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    event FundsWithdrawnEvent(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount
    );
    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    // ──────────────────────────────────────────────
    //  Setup
    // ──────────────────────────────────────────────

    function setUp() public {
        crowdFunding = new CrowdFunding();

        // Create labelled addresses
        creator = makeAddr("creator");
        backer1 = makeAddr("backer1");
        backer2 = makeAddr("backer2");
        backer3 = makeAddr("backer3");
        stranger = makeAddr("stranger");

        // Fund test accounts
        vm.deal(creator, 100 ether);
        vm.deal(backer1, 100 ether);
        vm.deal(backer2, 100 ether);
        vm.deal(backer3, 100 ether);
        vm.deal(stranger, 100 ether);
    }

    // ──────────────────────────────────────────────
    //  Helper Functions
    // ──────────────────────────────────────────────

    function _createDefaultCampaign() internal returns (uint256) {
        vm.prank(creator);
        return crowdFunding.createCampaign(GOAL, DURATION, IPFS_CID);
    }

    // ──────────────────────────────────────────────
    //  Campaign Creation Tests
    // ──────────────────────────────────────────────

    /// @notice Test successful campaign creation.
    function test_CreateCampaign() public {
        uint256 id = _createDefaultCampaign();
        assertEq(id, 1);
        assertEq(crowdFunding.campaignCount(), 1);

        (
            address _creator,
            uint256 _goal,
            uint256 _deadline,
            uint256 _raised,
            bytes32 _cid,
            CrowdFunding.Status _status
        ) = crowdFunding.getCampaign(id);

        assertEq(_creator, creator);
        assertEq(_goal, GOAL);
        assertEq(_deadline, block.timestamp + DURATION);
        assertEq(_raised, 0);
        assertEq(_cid, IPFS_CID);
        assertTrue(_status == CrowdFunding.Status.Active);
    }

    /// @notice Test creating multiple campaigns.
    function test_CreateMultipleCampaigns() public {
        uint256 id1 = _createDefaultCampaign();

        vm.prank(backer1);
        uint256 id2 = crowdFunding.createCampaign(5 ether, 3 days, keccak256("CID2"));

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(crowdFunding.campaignCount(), 2);
    }

    /// @notice Test that creating a campaign with zero goal reverts.
    function test_RevertWhen_CreateCampaignWithZeroGoal() public {
        vm.prank(creator);
        vm.expectRevert(CrowdFunding.GoalMustBeGreaterThanZero.selector);
        crowdFunding.createCampaign(0, DURATION, IPFS_CID);
    }

    /// @notice Test that creating a campaign with zero duration reverts.
    function test_RevertWhen_CreateCampaignWithZeroDuration() public {
        vm.prank(creator);
        vm.expectRevert(CrowdFunding.DeadlineMustBeInFuture.selector);
        crowdFunding.createCampaign(GOAL, 0, IPFS_CID);
    }

    // ──────────────────────────────────────────────
    //  Contribution Tests
    // ──────────────────────────────────────────────

    /// @notice Test successful contribution.
    function test_Contribute() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 3 ether}(id);

        (,,, uint256 raised,,) = crowdFunding.getCampaign(id);
        assertEq(raised, 3 ether);
        assertEq(crowdFunding.getContribution(id, backer1), 3 ether);
    }

    /// @notice Test multiple contributions from different backers.
    function test_MultipleContributors() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 3 ether}(id);

        vm.prank(backer2);
        crowdFunding.contribute{value: 4 ether}(id);

        vm.prank(backer3);
        crowdFunding.contribute{value: 2 ether}(id);

        (,,, uint256 raised,,) = crowdFunding.getCampaign(id);
        assertEq(raised, 9 ether);

        assertEq(crowdFunding.getContribution(id, backer1), 3 ether);
        assertEq(crowdFunding.getContribution(id, backer2), 4 ether);
        assertEq(crowdFunding.getContribution(id, backer3), 2 ether);
    }

    /// @notice Test that a backer can contribute multiple times.
    function test_MultipleContributionsSameBacker() public {
        uint256 id = _createDefaultCampaign();

        vm.startPrank(backer1);
        crowdFunding.contribute{value: 2 ether}(id);
        crowdFunding.contribute{value: 3 ether}(id);
        vm.stopPrank();

        assertEq(crowdFunding.getContribution(id, backer1), 5 ether);
    }

    /// @notice Test that contributing zero ETH reverts.
    function test_RevertWhen_ContributeZero() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        vm.expectRevert(CrowdFunding.ContributionMustBeGreaterThanZero.selector);
        crowdFunding.contribute{value: 0}(id);
    }

    /// @notice Test that contributing after the deadline reverts.
    function test_RevertWhen_ContributeAfterDeadline() public {
        uint256 id = _createDefaultCampaign();

        // Warp past the deadline
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(backer1);
        vm.expectRevert(CrowdFunding.CampaignDeadlineReached.selector);
        crowdFunding.contribute{value: 1 ether}(id);
    }

    /// @notice Test that contributing to a non-existent campaign reverts.
    function test_RevertWhen_ContributeToNonExistentCampaign() public {
        vm.prank(backer1);
        vm.expectRevert(CrowdFunding.CampaignDoesNotExist.selector);
        crowdFunding.contribute{value: 1 ether}(999);
    }

    // ──────────────────────────────────────────────
    //  Successful Campaign: Withdraw Tests
    // ──────────────────────────────────────────────

    /// @notice Test full successful campaign flow: goal reached → creator withdraws → funds transferred.
    function test_SuccessfulCampaignWithdraw() public {
        uint256 id = _createDefaultCampaign();

        // Contribute to meet the goal
        vm.prank(backer1);
        crowdFunding.contribute{value: 6 ether}(id);

        vm.prank(backer2);
        crowdFunding.contribute{value: 5 ether}(id);

        // Warp past deadline
        vm.warp(block.timestamp + DURATION + 1);

        uint256 creatorBalanceBefore = creator.balance;

        // Creator withdraws
        vm.prank(creator);
        crowdFunding.withdrawFunds(id);

        uint256 creatorBalanceAfter = creator.balance;
        assertEq(creatorBalanceAfter - creatorBalanceBefore, 11 ether);

        // Status should be FundsWithdrawn
        (,,,,, CrowdFunding.Status status) = crowdFunding.getCampaign(id);
        assertTrue(status == CrowdFunding.Status.FundsWithdrawn);
    }

    /// @notice Test that contributors cannot refund a successful campaign.
    function test_RevertWhen_RefundSuccessfulCampaign() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 10 ether}(id);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(backer1);
        vm.expectRevert(CrowdFunding.InvalidCampaignStatus.selector);
        crowdFunding.refund(id);
    }

    /// @notice Test that creator cannot withdraw before the deadline even if goal is met.
    function test_RevertWhen_WithdrawBeforeDeadline() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 15 ether}(id);

        // Goal is met but deadline hasn't passed
        vm.prank(creator);
        vm.expectRevert(CrowdFunding.DeadlineNotReached.selector);
        crowdFunding.withdrawFunds(id);
    }

    /// @notice Test that only the creator can withdraw.
    function test_RevertWhen_NonCreatorWithdraws() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 10 ether}(id);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(stranger);
        vm.expectRevert(CrowdFunding.OnlyCreatorCanCall.selector);
        crowdFunding.withdrawFunds(id);
    }

    /// @notice Test that creator cannot withdraw from a failed campaign.
    function test_RevertWhen_WithdrawFailedCampaign() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 1 ether}(id);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(creator);
        vm.expectRevert(CrowdFunding.InvalidCampaignStatus.selector);
        crowdFunding.withdrawFunds(id);
    }

    /// @notice Test that creator cannot withdraw twice.
    function test_RevertWhen_WithdrawTwice() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 10 ether}(id);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(creator);
        crowdFunding.withdrawFunds(id);

        // Try withdrawing again
        vm.prank(creator);
        vm.expectRevert(CrowdFunding.InvalidCampaignStatus.selector);
        crowdFunding.withdrawFunds(id);
    }

    // ──────────────────────────────────────────────
    //  Failed Campaign: Refund Tests
    // ──────────────────────────────────────────────

    /// @notice Test full failed campaign flow: deadline passes, each contributor gets exact refund.
    function test_RefundUnsuccessfulCampaign() public {
        uint256 id = _createDefaultCampaign();

        // Contribute but don't meet the goal
        vm.prank(backer1);
        crowdFunding.contribute{value: 3 ether}(id);

        vm.prank(backer2);
        crowdFunding.contribute{value: 2 ether}(id);

        // Warp past deadline
        vm.warp(block.timestamp + DURATION + 1);

        // Refund backer1
        uint256 backer1BalanceBefore = backer1.balance;
        vm.prank(backer1);
        crowdFunding.refund(id);
        assertEq(backer1.balance - backer1BalanceBefore, 3 ether);

        // Refund backer2
        uint256 backer2BalanceBefore = backer2.balance;
        vm.prank(backer2);
        crowdFunding.refund(id);
        assertEq(backer2.balance - backer2BalanceBefore, 2 ether);

        // Contributions should be zeroed out
        assertEq(crowdFunding.getContribution(id, backer1), 0);
        assertEq(crowdFunding.getContribution(id, backer2), 0);
    }

    /// @notice Test that a zero-contribution refund attempt reverts.
    function test_RevertWhen_ZeroContributionRefund() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 3 ether}(id);

        vm.warp(block.timestamp + DURATION + 1);

        // Stranger (non-contributor) tries to refund
        vm.prank(stranger);
        vm.expectRevert(CrowdFunding.NoContributionToRefund.selector);
        crowdFunding.refund(id);
    }

    /// @notice Test that refunding before the deadline reverts.
    function test_RevertWhen_RefundBeforeDeadline() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 3 ether}(id);

        // Deadline hasn't passed
        vm.prank(backer1);
        vm.expectRevert(CrowdFunding.DeadlineNotReached.selector);
        crowdFunding.refund(id);
    }

    /// @notice Test that a contributor cannot refund twice.
    function test_RevertWhen_RefundTwice() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 3 ether}(id);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(backer1);
        crowdFunding.refund(id);

        // Try refunding again
        vm.prank(backer1);
        vm.expectRevert(CrowdFunding.NoContributionToRefund.selector);
        crowdFunding.refund(id);
    }

    // ──────────────────────────────────────────────
    //  Edge Cases
    // ──────────────────────────────────────────────

    /// @notice Test campaign that exactly meets the goal.
    function test_ExactGoalMet() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: GOAL}(id);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(creator);
        crowdFunding.withdrawFunds(id);

        (,,,,, CrowdFunding.Status status) = crowdFunding.getCampaign(id);
        assertTrue(status == CrowdFunding.Status.FundsWithdrawn);
    }

    /// @notice Test campaign with no contributions at all.
    function test_RevertWhen_WithdrawNoContributions() public {
        uint256 id = _createDefaultCampaign();

        vm.warp(block.timestamp + DURATION + 1);

        // Creator cannot withdraw (goal not met)
        vm.prank(creator);
        vm.expectRevert(CrowdFunding.InvalidCampaignStatus.selector);
        crowdFunding.withdrawFunds(id);
    }

    /// @notice Test accessing a non-existent campaign.
    function test_RevertWhen_GetNonExistentCampaign() public {
        vm.expectRevert(CrowdFunding.CampaignDoesNotExist.selector);
        crowdFunding.getCampaign(999);
    }

    /// @notice Test getting contribution for non-existent campaign.
    function test_RevertWhen_GetContributionNonExistentCampaign() public {
        vm.expectRevert(CrowdFunding.CampaignDoesNotExist.selector);
        crowdFunding.getContribution(999, backer1);
    }

    // ──────────────────────────────────────────────
    //  Event Emission Tests
    // ──────────────────────────────────────────────

    /// @notice Test CampaignCreated event emission.
    function test_EmitCampaignCreated() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, true, address(crowdFunding));
        emit CampaignCreated(1, creator, GOAL, block.timestamp + DURATION);
        crowdFunding.createCampaign(GOAL, DURATION, IPFS_CID);
    }

    /// @notice Test Contributed event emission.
    function test_EmitContributed() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        vm.expectEmit(true, true, false, true, address(crowdFunding));
        emit Contributed(id, backer1, 5 ether);
        crowdFunding.contribute{value: 5 ether}(id);
    }

    /// @notice Test FundsWithdrawnEvent emission.
    function test_EmitFundsWithdrawn() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 10 ether}(id);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(creator);
        vm.expectEmit(true, true, false, true, address(crowdFunding));
        emit FundsWithdrawnEvent(id, creator, 10 ether);
        crowdFunding.withdrawFunds(id);
    }

    /// @notice Test RefundIssued event emission.
    function test_EmitRefundIssued() public {
        uint256 id = _createDefaultCampaign();

        vm.prank(backer1);
        crowdFunding.contribute{value: 3 ether}(id);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(backer1);
        vm.expectEmit(true, true, false, true, address(crowdFunding));
        emit RefundIssued(id, backer1, 3 ether);
        crowdFunding.refund(id);
    }
}
