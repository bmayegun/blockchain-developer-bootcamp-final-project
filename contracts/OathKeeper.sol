// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/// @title OathKeeper contract
/// @author Bisoye
/// @notice This contract gives you the ability to create oaths and its milestone and also manage withdrawals
/// @dev All function calls are currently implemented without side effects

contract OathKeeper {
    using SafeMath for uint256;

    uint256 private oathCount = 0;

    bool public stopped = false;

    address payable public owner;

    mapping(address => uint256) public pendingWithdrawals;

    mapping(uint256 => Oath) public oaths;

    struct Oath {
        uint256 Id;
        string body;
        uint256 timeCreated;
        uint256 deadline;
        uint256 oathValue;
        address payable oathGiver;
        address payable oathTaker;
        address payable defaultsRecipient;
        address payable completionRecipient;
        bool useVerifiers;
        uint256 milestoneCount;
    }

    mapping(uint256 => Milestone[]) public milestones;

    struct Milestone {
        // oathId acts as foreignkey to link milestone to oath
        string milestoneBody;
        uint256 confirmations;
        uint256 confirmationsSoFar;
        uint256 milestoneValue;
        uint256 milestoneCreated;
        uint256 milestoneDeadline;
        bool oathGiverVerified;
        bool oathTakerVerified;
        bool completed;
    }

    /**
     * MODIFIERS
     */

    modifier onlyOathGiver(address _oathGiver, uint256 _oathId) {
        require(
            _oathGiver == oaths[_oathId].oathGiver,
            "Access restricted to only Oath-Giver"
        );
        _;
    }

    modifier onlyOathTaker(address _oathTaker, uint256 _oathId) {
        require(
            _oathTaker == oaths[_oathId].oathTaker,
            "Access restricted to only Oath-Taker"
        );
        _;
    }

    modifier oathExists(uint256 _oathId) {
        require(oaths[_oathId].timeCreated != 0, "Oath does not exist");
        _;
    }

    modifier milestoneExists(uint256 _oathId, uint256 _milestoneId) {
        require(
            milestones[_oathId][_milestoneId].milestoneCreated != 0,
            "Milestone does not exist"
        );
        _;
    }

    modifier senderHasPendingWithdrawals(address _recipient) {
        require(
            pendingWithdrawals[_recipient] != 0,
            "Recipient has no pending withdrawals"
        );
        _;
    }

    modifier hasEnoughToCreateMilestone(
        address oathGiver,
        uint256 _milestoneValue
    ) {
        require(
            oathGiver.balance >= _milestoneValue,
            "Your balance is insufficient for creating equivalent milestone"
        );
        _;
    }

    modifier onlyOwner(address _sender) {
        require(_sender == owner, "Unauthorised");
        _;
    }

    modifier notEmergency() {
        require(!stopped, "Contract inactive");
        _;
    }

    modifier emergency() {
        require(stopped, "Contract execution paused");
        _;
    }

    /**
     * EVENTS
     */
    event oathCreated(uint256 indexed oathid);

    event milestoneCreatedForOath(uint256 indexed oathId);

    event oathGiverMarkMilestone(
        address oathGiver,
        uint256 indexed oathid,
        uint256 indexed milestoneId
    );

    event oathTakerMarkMilestone(
        address oathTaker,
        uint256 indexed oathid,
        uint256 indexed milestoneId
    );

    event withdrawalMade(address indexed recipient, uint256 indexed amount);

    event confirmationsComplete(uint256 indexed milestoneId);

    event recipientCredited(address recipient, uint256 amount);

    /**
     * METHODS
     */

    constructor() {
        owner = payable(msg.sender);
    }

    function pauseContract() public onlyOwner(msg.sender) {
        stopped = true;
    }

    function startContract() public onlyOwner(msg.sender) {
        stopped = false;
    }

    /// @notice create oath
    /// @param _deadline When oath expires
    /// @param _oathTaker (required) user who can mark milestone as done
    /// @param _defaultsRecipient (required) address to pay when milestone is missed
    /// @param _completionRecipient (required) address to pay when milestone is crushed
    /// @param _body some description of the milestone
    /// @return _oathId
    function createOath(
        uint256 _deadline,
        address payable _oathTaker,
        address payable _defaultsRecipient,
        address payable _completionRecipient,
        string memory _body
    ) public notEmergency returns (uint256 _oathId) {
        _oathId = oathCount;
        Oath memory newoath = Oath(
            _oathId,
            _body,
            block.timestamp,
            block.timestamp.add(_deadline),
            0,
            payable(msg.sender),
            _oathTaker,
            _defaultsRecipient,
            _completionRecipient,
            false,
            0
        );
        oaths[_oathId] = newoath;
        oathCount = oathCount.add(1);
        emit oathCreated(_oathId);
    }

    /// @notice
    /// @dev
    /// @return oathCount
    function getOathCount() public view returns (uint256) {
        return oathCount;
    }

    /// @notice Add milestone to existing oath
    /// @param _oathId The id of oath to add milestone
    /// @return updatedOathId
    function addMilestoneToOath(
        uint256 _oathId,
        string memory _milestoneBody,
        uint8 _confirmations,
        uint256 _milestoneDeadline
    )
        public
        payable
        notEmergency
        oathExists(_oathId)
        hasEnoughToCreateMilestone(msg.sender, msg.value)
        onlyOathGiver(msg.sender, _oathId)
        returns (uint256)
    {
        owner.transfer(msg.value);
        Milestone memory milestone = Milestone(
            _milestoneBody,
            _confirmations,
            0,
            msg.value,
            block.timestamp,
            block.timestamp.add(_milestoneDeadline),
            false,
            false,
            false
        );
        milestones[_oathId].push(milestone);
        oaths[_oathId].oathValue = oaths[_oathId].oathValue.add(msg.value);
        oaths[_oathId].milestoneCount = oaths[_oathId].milestoneCount.add(1);

        emit milestoneCreatedForOath(_oathId);
        return _oathId;
    }

    /// @notice
    /// @dev
    /// @param _oathId The id of oath to add milestone
    /// @return _oathId, _milestoneId
    function oathGiverMarkMilestoneAsDone(uint256 _oathId, uint256 _milestoneId)
        public
        notEmergency
        oathExists(_oathId)
        milestoneExists(_oathId, _milestoneId)
        onlyOathGiver(msg.sender, _oathId)
        returns (uint256, uint256)
    {
        // Milestone memory milestone = milestones[_oathId][_milestoneId];
        milestones[_oathId][_milestoneId].confirmationsSoFar = milestones[
            _oathId
        ][_milestoneId].confirmationsSoFar.add(1);
        milestones[_oathId][_milestoneId].oathGiverVerified = true;
        if (
            milestones[_oathId][_milestoneId].confirmationsSoFar ==
            milestones[_oathId][_milestoneId].confirmations
        ) {
            // Give ether value to success recipient
            milestones[_oathId][_milestoneId].completed = true;
            pendingWithdrawals[
                oaths[_oathId].completionRecipient
            ] = pendingWithdrawals[oaths[_oathId].completionRecipient].add(
                milestones[_oathId][_milestoneId].milestoneValue
            );
            emit confirmationsComplete(_milestoneId);
            emit recipientCredited(
                oaths[_oathId].completionRecipient,
                milestones[_oathId][_milestoneId].milestoneValue
            );
        }
        emit oathGiverMarkMilestone(msg.sender, _oathId, _milestoneId);
        return (_oathId, _milestoneId);
    }

    /// @notice
    /// @dev
    /// @param _oathId The id of oath to add milestone
    /// @return _oathId, _milestoneId
    function oathTakerMarkMilestoneAsDone(uint256 _oathId, uint256 _milestoneId)
        public
        notEmergency
        oathExists(_oathId)
        milestoneExists(_oathId, _milestoneId)
        onlyOathTaker(msg.sender, _oathId)
        returns (uint256, uint256)
    {
        Milestone storage milestone = milestones[_oathId][_milestoneId];
        milestone.confirmationsSoFar = milestone.confirmationsSoFar.add(1);
        milestone.oathTakerVerified = true;
        if (milestone.confirmationsSoFar == milestone.confirmations) {
            // Give ether value to success recipient
            milestone.completed = true;
            pendingWithdrawals[
                oaths[_oathId].completionRecipient
            ] = pendingWithdrawals[oaths[_oathId].completionRecipient].add(
                milestone.milestoneValue
            );
            emit confirmationsComplete(_milestoneId);
            emit recipientCredited(
                oaths[_oathId].completionRecipient,
                milestone.milestoneValue
            );
        }
        emit oathTakerMarkMilestone(msg.sender, _oathId, _milestoneId);
        return (_oathId, _milestoneId);
    }

    /// @notice
    /// @dev
    /// @return amount The ether value sent to recipient
    function withdrawFunds()
        public
        senderHasPendingWithdrawals(msg.sender)
        emergency
        returns (uint256)
    {
        uint256 amount = pendingWithdrawals[msg.sender];
        // Avoid re-entrancy by zeroing amount before sending;
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit withdrawalMade(msg.sender, amount);
        return amount;
    }

    /// @notice Fallback function
    fallback() external payable {}

    /// @notice Fallback function
    receive() external payable {}

    // function oathVerifierMarkMilestoneAsDone(uint _oathId) public returns (uint) {
    //     milestones[_oathId].confirmations++;
    //     milestones[_oathId].oathGiverVerified = true;
    // }
}
