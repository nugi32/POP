// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../Pipe/StateVarPipes.sol";

abstract contract stakeUtils is StateVarPipes {
 
    function stateVarUtils_init(address _stateVar) internal {
        stateVar = stateVariable(_stateVar);
    }
    
    enum TaskValue {Low, MidleLow,  Midle, MidleHigh, High, UltraHigh}

       function ___getProjectValueCategory(uint256 _value) internal view returns (TaskValue) {
   
        if (_value <= ___getCategoryLow()) {
            return TaskValue.Low;
        } else if (_value <= ___getCategoryMidleLow()) {
            return TaskValue.MidleLow;
        } else if (_value <= ___getCategoryMidle()) {
            return TaskValue.Midle;
        } else if (_value <= ___getCategoryMidleHigh()) {
            return TaskValue.MidleHigh;
        } else if (_value <= ___getCategoryHigh()) {
            return TaskValue.High;
        } else {
            return TaskValue.UltraHigh;
        }
    }


function ___getCreatorStake(uint256 __value) internal view returns (uint256) {

    TaskValue category = ___getProjectValueCategory(__value);

    if (category == TaskValue.Low) {
        return ___getStakeLow();
    } else if (category == TaskValue.MidleLow) {
        return ___getStakeMidLow();
    } else if (category == TaskValue.Midle) {
        return ___getStakeMid();
    } else if (category == TaskValue.MidleHigh) {
        return ___getStakeMidHigh();
    } else if (category == TaskValue.High) {
        return ___getStakeHigh();
    } else {
        return ___getStakeUltraHigh();
    }
}
}