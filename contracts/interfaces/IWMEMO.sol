// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface IWMEMO {
    function wrap( uint _amount ) external returns ( uint );

    function unwrap( uint _amount ) external returns ( uint );
}