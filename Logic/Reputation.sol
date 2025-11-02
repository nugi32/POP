// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IMainReputation {
    function seeMyReputation(address _user) external view returns (uint256);
}

abstract contract UserReputation is Initializable {
    IMainReputation public MainContract;

    function __UserReputation_init(
        address _MainContract
    ) 
        public 
        //onlyInitializing 
    {
        require(_MainContract != address(0), "invalid main addr");

        MainContract = IMainReputation(_MainContract);
    }

    // Forward point lokal ke main.sol
    function _seeMyReputation(address _user) internal view returns (uint8) {
    uint256 rep = MainContract.seeMyReputation(_user);
    return uint8(rep);
}
}