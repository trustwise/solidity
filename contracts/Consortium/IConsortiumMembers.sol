pragma solidity ^0.5.8;

interface IConsortiumMembers {

    /**
     * @dev Get consortium member addresses list.
     * @return Consortium member addresses list.
     */
    function getMembers() external view returns (address[] memory);

    /**
     * @dev Check whether address is consortium member.
     * @param _address Address to be checked.
     * @return True if given address is consortium member.
     */
    function isMember(address) external view returns (bool);
}
