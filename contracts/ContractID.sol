pragma solidity ^0.5.8;

/**
 * @title Contract ID contract
 * @author Vladyslav Lupashevskyi
 * @dev This contract provides identification (contract type and contract sub type)
 * and version information for smart contracts.
 */
contract ContractID {
    /**
     * @dev Contract type
     * @return String value of contract type
     */
    function ContractType() public view returns(string memory);

    /**
     * @dev Contract sub-type
     * @return String value of contract sub-type
     */
    function ContractSubType() public view returns(string memory);

    /**
     * @dev Contract version
     * @return Contract version (uint256)
     */
    function ContractVersion() public view returns(uint256);

    /**
     * @dev Contract type hash
     * @return Keccak256 hash of contract type string
     */
    function ContractTypeHash() public view returns(bytes32) {
        return keccak256(abi.encodePacked(ContractType()));
    }

    /**
     * @dev Contract sub-type hash
     * @return Keccak256 hash of contract sub-type string
     */
    function ContractSubTypeHash() public view returns(bytes32) {
        return keccak256(abi.encodePacked(ContractSubType()));
    }

    /**
     * @dev Is contract ID derivative.
     * Used for checking whether the address implements ContractID interface.
     * @return True
     */
    function isContractIdDerivative() external pure returns (bool) {
        return true;
    }
}
