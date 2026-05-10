// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CrowdFunding — A decentralised crowdfunding platform
/// @author Prajwal
/// @notice Create campaigns, contribute ETH, withdraw on success, or refund on failure.
/// @dev Uses OpenZeppelin ReentrancyGuard. Campaign descriptions are stored off-chain via IPFS CIDs.
contract CrowdFunding is ReentrancyGuard {
    // ──────────────────────────────────────────────
    //  Custom Errors (gas-efficient vs revert strings)
    // ──────────────────────────────────────────────

    /// @dev Thrown when a zero goal amount is provided.
    error GoalMustBeGreaterThanZero();
    /// @dev Thrown when the provided deadline is not in the future.
    error DeadlineMustBeInFuture();
    /// @dev Thrown when attempting to contribute zero ETH.
    error ContributionMustBeGreaterThanZero();
    /// @dev Thrown when attempting to interact with a non-existent campaign.
    error CampaignDoesNotExist();
    /// @dev Thrown when the campaign is not in the expected status.
    error InvalidCampaignStatus();
    /// @dev Thrown when attempting to contribute after the campaign deadline.
    error CampaignDeadlineReached();
    /// @dev Thrown when a non-creator attempts a creator-only action.
    error OnlyCreatorCanCall();
    /// @dev Thrown when the campaign deadline has not yet passed.
    error DeadlineNotReached();
    /// @dev Thrown when a contributor with zero contribution attempts a refund.
    error NoContributionToRefund();
    /// @dev Thrown when an ETH transfer fails.
    error TransferFailed();

    // ──────────────────────────────────────────────
    //  Enums
    // ──────────────────────────────────────────────

    /// @notice Campaign lifecycle status.
    enum Status {
        Active,
        Successful,
        Failed,
        FundsWithdrawn
    }

    // ──────────────────────────────────────────────
    //  Structs
    // ──────────────────────────────────────────────

    /// @notice On-chain campaign data. Full descriptions are stored off-chain (IPFS CID).
    struct Campaign {
        address creator;
        uint256 goalWei;
        uint256 deadlineTimestamp;
        uint256 raisedWei;
        bytes32 ipfsCID;
        Status status;
    }

    // ──────────────────────────────────────────────
    //  State Variables
    // ──────────────────────────────────────────────

    /// @notice Auto-incrementing campaign ID counter.
    uint256 public campaignCount;

    /// @notice Mapping from campaign ID to Campaign struct.
    mapping(uint256 => Campaign) public campaigns;

    /// @notice Mapping from campaign ID => contributor address => amount contributed (wei).
    mapping(uint256 => mapping(address => uint256)) public contributions;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    /// @notice Emitted when a new campaign is created.
    /// @param campaignId The ID of the newly created campaign.
    /// @param creator The address of the campaign creator.
    /// @param goalWei The funding goal in wei.
    /// @param deadlineTimestamp The campaign deadline as a Unix timestamp.
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 goalWei,
        uint256 deadlineTimestamp
    );

    /// @notice Emitted when a contribution is made.
    /// @param campaignId The campaign that received the contribution.
    /// @param contributor The address of the contributor.
    /// @param amount The amount contributed in wei.
    event Contributed(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    /// @notice Emitted when a creator withdraws funds from a successful campaign.
    /// @param campaignId The campaign from which funds were withdrawn.
    /// @param creator The address of the creator who withdrew.
    /// @param amount The total amount withdrawn in wei.
    event FundsWithdrawnEvent(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount
    );

    /// @notice Emitted when a contributor receives a refund from a failed campaign.
    /// @param campaignId The campaign from which the refund was issued.
    /// @param contributor The address of the contributor who was refunded.
    /// @param amount The amount refunded in wei.
    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    /// @dev Ensures the campaign exists.
    modifier campaignExists(uint256 _campaignId) {
        if (_campaignId == 0 || _campaignId > campaignCount) {
            revert CampaignDoesNotExist();
        }
        _;
    }

    // ──────────────────────────────────────────────
    //  External / Public Functions
    // ──────────────────────────────────────────────

    /// @notice Create a new crowdfunding campaign.
    /// @param _goalWei The funding goal in wei. Must be greater than zero.
    /// @param _durationSeconds Duration of the campaign in seconds from now.
    /// @param _ipfsCID IPFS content identifier (CID) for the off-chain campaign metadata.
    /// @return campaignId The ID of the newly created campaign.
    function createCampaign(
        uint256 _goalWei,
        uint256 _durationSeconds,
        bytes32 _ipfsCID
    ) external returns (uint256 campaignId) {
        if (_goalWei == 0) revert GoalMustBeGreaterThanZero();
        if (_durationSeconds == 0) revert DeadlineMustBeInFuture();

        unchecked {
            campaignId = ++campaignCount;
        }

        uint256 deadline = block.timestamp + _durationSeconds;

        campaigns[campaignId] = Campaign({
            creator: msg.sender,
            goalWei: _goalWei,
            deadlineTimestamp: deadline,
            raisedWei: 0,
            ipfsCID: _ipfsCID,
            status: Status.Active
        });

        emit CampaignCreated(campaignId, msg.sender, _goalWei, deadline);
    }

    /// @notice Contribute ETH to an active campaign before its deadline.
    /// @param _campaignId The ID of the campaign to contribute to.
    function contribute(uint256 _campaignId)
        external
        payable
        campaignExists(_campaignId)
    {
        if (msg.value == 0) revert ContributionMustBeGreaterThanZero();

        // Cache storage pointer for gas efficiency
        Campaign storage campaign = campaigns[_campaignId];

        if (campaign.status != Status.Active) revert InvalidCampaignStatus();
        if (block.timestamp >= campaign.deadlineTimestamp) {
            revert CampaignDeadlineReached();
        }

        campaign.raisedWei += msg.value;
        contributions[_campaignId][msg.sender] += msg.value;

        emit Contributed(_campaignId, msg.sender, msg.value);
    }

    /// @notice Withdraw funds from a successful campaign. Only the creator may call this,
    ///         and only after the deadline has passed and the goal has been met.
    /// @param _campaignId The ID of the campaign to withdraw from.
    function withdrawFunds(uint256 _campaignId)
        external
        nonReentrant
        campaignExists(_campaignId)
    {
        Campaign storage campaign = campaigns[_campaignId];

        if (msg.sender != campaign.creator) revert OnlyCreatorCanCall();
        if (block.timestamp < campaign.deadlineTimestamp) {
            revert DeadlineNotReached();
        }

        // Finalise status if still Active
        _finaliseStatus(_campaignId);

        if (campaign.status != Status.Successful) {
            revert InvalidCampaignStatus();
        }

        // Cache amount before state change (Checks-Effects-Interactions)
        uint256 amount = campaign.raisedWei;
        campaign.status = Status.FundsWithdrawn;

        // Interaction: transfer ETH
        (bool success,) = payable(campaign.creator).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit FundsWithdrawnEvent(_campaignId, campaign.creator, amount);
    }

    /// @notice Refund a contributor's ETH from a failed campaign.
    ///         The campaign must have passed its deadline without meeting the goal.
    /// @param _campaignId The ID of the campaign to get a refund from.
    function refund(uint256 _campaignId)
        external
        nonReentrant
        campaignExists(_campaignId)
    {
        Campaign storage campaign = campaigns[_campaignId];

        if (block.timestamp < campaign.deadlineTimestamp) {
            revert DeadlineNotReached();
        }

        // Finalise status if still Active
        _finaliseStatus(_campaignId);

        if (campaign.status != Status.Failed) {
            revert InvalidCampaignStatus();
        }

        uint256 contributedAmount = contributions[_campaignId][msg.sender];
        if (contributedAmount == 0) revert NoContributionToRefund();

        // Effects: zero out contribution before transfer
        contributions[_campaignId][msg.sender] = 0;
        campaign.raisedWei -= contributedAmount;

        // Interaction: transfer ETH
        (bool success,) = payable(msg.sender).call{value: contributedAmount}("");
        if (!success) revert TransferFailed();

        emit RefundIssued(_campaignId, msg.sender, contributedAmount);
    }

    // ──────────────────────────────────────────────
    //  View Functions
    // ──────────────────────────────────────────────

    /// @notice Retrieve full campaign details.
    /// @param _campaignId The ID of the campaign.
    /// @return creator The campaign creator's address.
    /// @return goalWei The campaign goal in wei.
    /// @return deadlineTimestamp The campaign deadline (Unix timestamp).
    /// @return raisedWei The total amount raised in wei.
    /// @return ipfsCID The IPFS CID for off-chain metadata.
    /// @return status The current campaign status.
    function getCampaign(uint256 _campaignId)
        external
        view
        campaignExists(_campaignId)
        returns (
            address creator,
            uint256 goalWei,
            uint256 deadlineTimestamp,
            uint256 raisedWei,
            bytes32 ipfsCID,
            Status status
        )
    {
        Campaign storage c = campaigns[_campaignId];
        return (
            c.creator,
            c.goalWei,
            c.deadlineTimestamp,
            c.raisedWei,
            c.ipfsCID,
            c.status
        );
    }

    /// @notice Get the contribution amount of a specific contributor to a campaign.
    /// @param _campaignId The ID of the campaign.
    /// @param _contributor The address of the contributor.
    /// @return amount The amount contributed in wei.
    function getContribution(uint256 _campaignId, address _contributor)
        external
        view
        campaignExists(_campaignId)
        returns (uint256 amount)
    {
        return contributions[_campaignId][_contributor];
    }

    // ──────────────────────────────────────────────
    //  Internal Functions
    // ──────────────────────────────────────────────

    /// @dev Finalise campaign status after deadline. Moves from Active to Successful or Failed.
    /// @param _campaignId The ID of the campaign to finalise.
    function _finaliseStatus(uint256 _campaignId) internal {
        Campaign storage campaign = campaigns[_campaignId];

        if (campaign.status != Status.Active) return;
        if (block.timestamp < campaign.deadlineTimestamp) return;

        if (campaign.raisedWei >= campaign.goalWei) {
            campaign.status = Status.Successful;
        } else {
            campaign.status = Status.Failed;
        }
    }
}
