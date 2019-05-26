pragma solidity ^0.5.8;

import "../../Proxies/ConsortiumUpgradeabilityProxy.sol";

contract ConsortiumMembersProxy is ConsortiumUpgradeabilityProxy {
    constructor() ConsortiumUpgradeabilityProxy(0xBCcF68fC126F27D584562686F972B06a95675BBf) public {}

    function _owner() internal view returns (address) {
        return address(this);
    }
}
