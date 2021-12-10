// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface IStaking {
    function stake( uint _amount, address _recipient ) external returns ( bool );
    function claim( address _recipient ) external;
    function unstake( uint _amount, bool _trigger ) external;
}