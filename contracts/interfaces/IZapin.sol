// SPDX-License-Identifier: GPL-3.0

import "./ITimeBondDepository.sol";

pragma solidity >=0.7.0 <0.9.0;

interface IZapin {
    function ZapInLp(
        address _FromTokenContractAddress,
        ITimeBondDepository _bondDepository,
        uint256 _amount,
        uint256 _minPoolTokens,
        address _swapTarget,
        bytes calldata swapData,
        bool transferResidual,
        uint _bondMaxPrice,
        address _to
    ) external payable returns (uint256);
    
    function ZapIn(
        address _FromTokenContractAddress,
        ITimeBondDepository _bondDepository,
        uint256 _amount,
        uint256 _minReturnTokens,
        address _swapTarget,
        bytes calldata swapData,
        uint _bondMaxPrice,
        address _to
    ) external payable returns (uint256);
}