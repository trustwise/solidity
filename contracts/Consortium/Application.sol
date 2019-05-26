pragma solidity ^0.5.8;
pragma experimental ABIEncoderV2;

/**
 * @title Application abstract contract
 * @author Vladyslav Lupashevskyi
 * @dev This contract provides features invite/apply features for consortium members
 * and validators contract. First the address gets invited, then application should be submitted
 * by invitee (the address becomes an applicant). Finally the manager address should either confirm
 * or reject the application. This contract provides abstract functions which define manager address,
 * whether the address can be invited and callback function when application is confirmed.
 */
contract Application {
    /// Invitees
    address[] invitees;
    mapping (address => uint256) inviteeIndex;

    /// Applicants
    address[] applicants;
    mapping (address => uint256) applicantIndex;

    // Reserved memory (10 x 32 bytes) for future upgrades
    uint256 _application_reserved_0;
    uint256 _application_reserved_1;
    uint256 _application_reserved_2;
    uint256 _application_reserved_3;
    uint256 _application_reserved_4;
    uint256 _application_reserved_5;
    uint256 _application_reserved_6;
    uint256 _application_reserved_7;
    uint256 _application_reserved_8;
    uint256 _application_reserved_9;

    event Invited(address indexed invitee);
    event InvitationCancelled(address indexed invitee);
    event Applied(address indexed applicant);
    event ApplicationRevoked(address indexed applicant);
    event ApplicationConfirmed(address indexed applicant);

    /**
     * @dev Invite address. Adds invitee address to the invitees list.
     * Can be executed if `canManage` function does not revert transaction with given msg.sender address.
     * Invitee is added if `canBeInvited` function returns true with given invitee address.
     * @param invitee Invitee address
     */
    function invite(address invitee) public {
        canManage(msg.sender);
        require(canBeInvited(invitee), "Cannot be invited");
        _addInvitee(invitee);
        emit Invited(invitee);
    }

    /**
     * @dev Cancel invitation. Removes invitee address from the invitees list.
     * Can be executed if `canManage` function does not revert transaction with given msg.sender address.
     * Cannot be called if invitee has already applied.
     * @param invitee Invitee address
     */
    function cancelInvitation(address invitee) public {
        canManage(msg.sender);
        require(!isApplicant(invitee), "Cannot cancel the invitation for already applied address");
        _removeInvitee(invitee);
        emit InvitationCancelled(invitee);
    }

    /**
     * @dev Submit application. Adds invitee to the applicants list.
     * Can be executed only by invitees.
     * Cannot be called if invitee has already applied.
     */
    function submitApplication() public {
        require(isInvitee(msg.sender), "Not invited addresses are not allowed to submit applications");
        require(!isApplicant(msg.sender), "Already applied");
        _addApplicant(msg.sender);
        emit Applied(msg.sender);
    }

    /**
     * @dev Revoke application. Removes applicant address from invitees and applicants lists.
     * Can be executed if `canManage` function does not revert transaction with given msg.sender address.
     * @param applicant Applicant address
     */
    function revokeApplication(address applicant) public {
        canManage(msg.sender);
        require(isApplicant(applicant), "Not an applicant");
        _removeInvitee(applicant);
        _removeApplicant(applicant);
        emit ApplicationRevoked(applicant);
    }

    /**
     * @dev Confirm application.
     * Triggers `onApplicationConfirmed` abstract function.
     * Removes applicant address from invitees and applicants lists.
     * Can be executed if `canManage` function does not revert transaction with given msg.sender address.
     * @param applicant Applicant address
     */
    function confirmApplication(address applicant) public {
        canManage(msg.sender);
        require(isApplicant(applicant), "Not an applicant");
        _removeInvitee(applicant);
        _removeApplicant(applicant);
        onApplicationConfirmed(applicant);
        emit ApplicationConfirmed(applicant);
    }

    /**
     * @dev Get invitees list.
     * @return List of invitee addresses
     */
    function getInvitees() public view returns(address[] memory) {
        return invitees;
    }

    /**
     * @dev Get applicants list.
     * @return List of applicant addresses
     */
    function getApplicants() public view returns(address[] memory) {
        return applicants;
    }

    /**
     * @dev Check whether address is an invitee.
     * @param _address Address to be checked.
     * @return True if given address is an invitee.
     */
    function isInvitee(address _address) public view returns(bool) {
        if (invitees.length == 0) return false;
        return invitees[inviteeIndex[_address]] == _address;
    }

    /**
     * @dev Check whether address is an applicant.
     * @param _address Address to be checked.
     * @return True if given address is an applicant.
     */
    function isApplicant(address _address) public view returns(bool) {
        if (applicants.length == 0) return false;
        return applicants[applicantIndex[_address]] == _address;
    }

    /**
     * @dev Helper function for adding invitee to the invitees list.
     * @param member Address of the invitee to be added.
     */
    function _addInvitee(address invitee) internal {
        require(!isInvitee(invitee), "Already an invitee");
        inviteeIndex[invitee] = invitees.push(invitee) - 1;
    }

    /**
     * @dev Helper function for removing invitee from the invitees list.
     * @param member Address of the invitee to be removed.
     */
    function _removeInvitee(address invitee) internal {
        require(isInvitee(invitee), "Not an invitee");
        uint256 indexToRemove = inviteeIndex[invitee];
        address addressToMove = invitees[invitees.length - 1];
        invitees[indexToRemove] = addressToMove;
        inviteeIndex[addressToMove] = indexToRemove;
        inviteeIndex[invitee] = 0;
        invitees.length--;
    }

    /**
     * @dev Helper function for adding applicant to the applicants list.
     * @param member Address of the applicant to be added.
     */
    function _addApplicant(address applicant) internal {
        require(!isApplicant(applicant), "Already an applicant");
        applicantIndex[applicant] = applicants.push(applicant) - 1;
    }

    /**
     * @dev Helper function for removing applicant from the applicants list.
     * @param member Address of the applicant to be removed.
     */
    function _removeApplicant(address applicant) internal {
        require(isApplicant(applicant), "Not an applicant");
        uint256 indexToRemove = applicantIndex[applicant];
        address addressToMove = applicants[applicants.length - 1];
        applicants[indexToRemove] = addressToMove;
        applicantIndex[addressToMove] = indexToRemove;
        applicantIndex[applicant] = 0;
        applicants.length--;
    }

    /**
     * @dev Abstract function which defines which address is allowed to call management functions
     * such as: `invite(address)`, `cancelInvitation(address)`, `confirmApplication(address)`
     * and `revokeApplication(address).`
     * @param msg.sender
     */
    function canManage(address) internal;

    /**
     * @dev Abstract function which defines whether address is allowed to be invited.
     * @param Invitee address
     */
    function canBeInvited(address) internal view returns(bool);

    /**
     * @dev Abstract function which is called when application is confirmed.
     * @param Confirmed applicant address
     */
    function onApplicationConfirmed(address) internal;
}
