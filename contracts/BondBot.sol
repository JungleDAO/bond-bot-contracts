// SPDX-License-Identifier: GPL-3.0

import "./interfaces/IERC20.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IZapin.sol";
import "./interfaces/ITimeBondDepository.sol";
import "./libraries/SafeERC20.sol";


pragma solidity >=0.7.0 <0.9.0;

contract BondBot {
    
    using SafeERC20 for IERC20;
    
    address private owner;
    
    IERC20 private constant time = IERC20(0xb54f16fB19478766A268F172C9480f8da1a7c9C3);
    IERC20 private constant memo = IERC20(0x136Acd46C134E8269052c62A67042D6bDeDde3C9);
    IStaking private constant staking = IStaking(0x4456B87Af11e87E329AB7d7C7A246ed1aC2168B9);
    IZapin private constant zapin = IZapin(0xc669dC61aF974FdF50758d95306e4083D36f1430);
    
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    event Withdraw(address token, uint amount);
    
    // modifier to check if caller is owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
    
    constructor(
        address _owner
    ) {
        owner = _owner;
        emit OwnerSet(address(0), owner);
        time.approve(address(zapin), type(uint256).max);
    }
    
    function bondLp(address bondAddress, uint amount, uint minAmount, address swapTarget, bytes calldata swapData, uint256 maxPrice) public onlyOwner {
        _unstakeMemo(amount);
        require(time.balanceOf(address(this)) == amount);
        _claimPendingRewards(bondAddress);
        _zapinLp(bondAddress, amount, minAmount, swapTarget, swapData, maxPrice);
    }
    
    function bond(address bondAddress, uint amount, uint minAmount, address swapTarget, bytes calldata swapData, uint256 maxPrice) public onlyOwner {
        _unstakeMemo(amount);
        require(time.balanceOf(address(this)) == amount);
        _claimPendingRewards(bondAddress);
        _zapin(bondAddress, amount, minAmount, swapTarget, swapData, maxPrice);
    }
    
    function withdraw(address tokenToWithdraw, uint amount) public onlyOwner {
        require(amount <= _getTokenAmount(tokenToWithdraw), "Not enough balance");
        IERC20( tokenToWithdraw ).approve( address(this), amount);
        IERC20( tokenToWithdraw ).safeTransferFrom( address(this), owner, amount);
        emit Withdraw(tokenToWithdraw, amount);
    }
    
    function getTokenBalance(address token) public view returns( uint ) {
        return IERC20( token ).balanceOf(address(this));
    }
    
    function _getTokenAmount(address token) private view returns (uint) {
        return IERC20( token ).balanceOf(address(this));
    }
    
    function _getMemoAmount() private view returns(uint) {
        return memo.balanceOf(address(this));
    }
    
    function _unstakeMemo(uint amount) private {
        require(amount <= _getMemoAmount(), "Not enough Memo balance");
        memo.approve( address(staking), amount );
        staking.unstake(amount, true);
    }
    
    function _claimPendingRewards(address bondAddress) private {
        uint claimable = ITimeBondDepository( bondAddress ).pendingPayoutFor( address(this));
        if (claimable > 0) {
            ITimeBondDepository( bondAddress ).redeem(address(this), true);    
        }
    }
    
    function _zapinLp(address bondAddress, uint amount, uint minAmount, address swapTarget, bytes calldata swapData, uint256 maxPrice) private {
        zapin.ZapInLp(
            address(time),
            ITimeBondDepository( bondAddress ),
            amount,
            minAmount,
            swapTarget,
            swapData,
            false,
            maxPrice,
            address(this)
        );
    }
    
    function _zapin(address bondAddress, uint amount, uint minAmount, address swapTarget, bytes calldata swapData, uint256 maxPrice) private {
        zapin.ZapIn(
            address(time),
            ITimeBondDepository( bondAddress ),
            amount,
            minAmount,
            swapTarget,
            swapData,
            maxPrice,
            address(this)
        );
    }
}