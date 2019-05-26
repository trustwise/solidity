pragma solidity ^0.5.1;

import "./Proxy.sol";
import "../ContractID.sol";

/**
 * @title UpgradeabilityProxy
 * @dev This contract implements a proxy that allows to change the
 * implementation address to which it will delegate.
 * Such a change is called an implementation upgrade.
 */
contract UpgradeabilityProxy is Proxy {
    /**
    * @dev Emitted when the implementation is upgraded.
    * @param implementation Address of the new implementation.
    */
    event Upgraded(address implementation);

    /**
    * @dev Storage slot with the address of the current implementation.
    * This is the keccak-256 hash of "io.trustwise.proxy.implementation", and is
    * validated in the constructor.
    */
    bytes32 private constant IMPLEMENTATION_SLOT = 0x70b5fd018d61794b325d7d08404cce3f770995dbf987a34ac70dbc047e415bbd;

    /**
    * @dev Contract constructor.
    * @param _implementation Address of the initial implementation.
    */
    constructor(address _implementation) public {
        assert(IMPLEMENTATION_SLOT == keccak256("io.trustwise.proxy.implementation"));

        bytes32 slot = IMPLEMENTATION_SLOT;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            sstore(slot, _implementation)
        }
    }

    /**
    * @dev Returns the current implementation.
    * @return Address of the current implementation
    */
    function _implementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            impl := sload(slot)
        }
    }

    /**
    * @dev Upgrades the proxy to a new implementation.
    * @param newImplementation Address of the new implementation.
    */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
    * @dev Sets the implementation address of the proxy.
    * @param newImplementation Address of the new implementation.
    */
    function _setImplementation(address newImplementation) private {
        require(ContractID(newImplementation).isContractIdDerivative(), "Cannot set a proxy implementation to a non-ContractID type");

        bytes32 slot = IMPLEMENTATION_SLOT;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            sstore(slot, newImplementation)
        }
    }
}
