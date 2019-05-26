pragma solidity ^0.5.1;

import "./UpgradeabilityProxy.sol";

contract ConsortiumUpgradeabilityProxy is UpgradeabilityProxy {
    /**
    * @dev Modifier to check whether the `msg.sender` is the owner.
    * If it is, it will run the function. Otherwise, it will delegate the call
    * to the implementation.
    */
    modifier ifOwner() {
        if (msg.sender == _owner()) {
            _;
        } else {
            _fallback();
        }
    }

    constructor(address _implementation) UpgradeabilityProxy(_implementation) public {}

    /**
    * @dev Upgrade the backing implementation of the proxy.
    * Only the owner can call this function.
    * @param newImplementation Address of the new implementation.
    */
    function upgradeTo(address newImplementation) external ifOwner {
        _upgradeTo(newImplementation);
    }

    /**
    * @dev Upgrade the backing implementation of the proxy and call a function
    * on the new implementation.
    * This is useful to initialize the proxied contract.
    * @param newImplementation Address of the new implementation.
    * @param data Data to send as msg.data in the low level call.
    * It should include the signature and the parameters of the function to be
    * called, as described in
    * https://solidity.readthedocs.io/en/develop/abi-spec.html#function-selector-and-argument-encoding.
    */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable ifOwner {
        _upgradeTo(newImplementation);
        // solium-disable-next-line security/no-call-value
        (bool success,) = address(this).call.value(msg.value)(data);
        require(success, "upgradeToAndCall call failed");
    }

    function _owner() internal view returns (address);

}
