// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface ITimeBondDepository {
    function deposit( uint _amount, uint _maxPrice, address _depositor) external returns ( uint );
    function pendingPayoutFor( address _depositor ) external view returns ( uint );
    function redeem( address _recipient, bool _stake ) external returns ( uint );
}