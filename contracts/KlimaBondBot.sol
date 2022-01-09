// SPDX-License-Identifier: GPL-3.

import "./interfaces/IERC20.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IZapin.sol";
import "./interfaces/ITimeBondDepository.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";


pragma solidity >=0.7.0 <0.9.0;

contract BondBot {
    
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // IUniswapV2Factory private constant joeFactory =
    //     IUniswapV2Factory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);

    // IUniswapV2Router02 private constant joeRouter =
    //     IUniswapV2Router02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);

    address private constant usdc =
        address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    address private constant klimaAddress =
        address(0x4e78011Ce80ee02d2c3e649Fb657E45898257815);

    uint256 private constant deadline =
        0xf000000000000000000000000000000000000000000000000000000000000000;
    
    address private owner;
    address private moderator;
    IUniswapV2Factory private factory;
    IUniswapV2Router02 private router;
    
    IERC20 private constant time = IERC20(0x4e78011Ce80ee02d2c3e649Fb657E45898257815);
    IERC20 private constant memo = IERC20(0xb0C22d8D350C67420f06F48936654f567C73E8C8);
    IStaking private constant staking = IStaking(0x25d28a24Ceb6F81015bB0b2007D795ACAc411b4d);
    
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    event Withdraw(address token, uint amount);
    event Bond(address bondAddress, uint256 amount);
    event BondLP(address bondAddress, uint256 amount);
    
    // modifier to check if caller is owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    modifier onlyModerator() {
        require(msg.sender == moderator, "Caller is not moderator");
        _;
    }
    
    constructor(
        address _owner,
        address _moderator,
        IUniswapV2Factory _factory,
        IUniswapV2Router02 _router
    ) {
        owner = _owner;
        moderator = _moderator;
        factory = _factory;
        router = _router;

        emit OwnerSet(address(0), owner);
    }
    
    function bondLp(address bondAddress, address lptoken, address tokenA, address tokenB, uint amount, uint256 maxPrice, bool isDoubleSwap) public onlyOwner {
        _unstakeMemo(amount);
        if (isDoubleSwap) {
            amount = _token2Token(klimaAddress, tokenA, amount);
        }
        _unstakeAndSwapLp(bondAddress, tokenA, tokenB, amount);
        uint256 amountA = IERC20( tokenA ).balanceOf(address(this));
        uint256 amountB = IERC20( tokenB ).balanceOf(address(this));
        uint256 minAmountA = amountA.mul(99) / 100;
        uint256 minAmountB = amountB.mul(99) / 100;
        _addLiquidity(tokenB, tokenA, amountB, amountA, minAmountB, minAmountA);
        uint256 tokenBought = IERC20( lptoken ).balanceOf(address(this));
        require(tokenBought > 0, "Not enought lp token");
        IERC20( lptoken ).approve( bondAddress, tokenBought);
        ITimeBondDepository( bondAddress ).deposit(tokenBought, maxPrice, address(this));
        uint256 timeAmount = time.balanceOf(address(this));
        if (timeAmount > 0) {
            _stakeTime();
        }
        emit BondLP(bondAddress, tokenBought);
    }
    
    function bond(address bondAddress, uint256 amount, address tokenIn, address tokenOut, uint256 maxPrice) public onlyOwner {
        _unstakeMemo(amount);
        require(time.balanceOf(address(this)) == amount);
        _claimPendingRewards(bondAddress);
        uint256 tokenBought = _token2Token(tokenIn, tokenOut, amount);
        IERC20( tokenOut ).approve( bondAddress, tokenBought);
        ITimeBondDepository( bondAddress ).deposit(tokenBought, maxPrice, address(this));
        uint256 timeAmount = time.balanceOf(address(this));
        if (timeAmount > 0) {
            _stakeTime();
        }
        emit Bond(bondAddress, amount);
    }

    function withdraw(address tokenToWithdraw, uint amount) public onlyModerator {
        require(amount <= _getTokenAmount(tokenToWithdraw), "Not enough balance");
        IERC20( tokenToWithdraw ).approve( address(this), amount);
        IERC20( tokenToWithdraw ).safeTransferFrom( address(this), moderator, amount);
        emit Withdraw(tokenToWithdraw, amount);
    }
    
    function getTokenBalance(address token) public view returns( uint ) {
        return IERC20( token ).balanceOf(address(this));
    }

    function changeOwner(address newOwner) public onlyModerator {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnerSet(oldOwner, newOwner);
    }

    function updateExchange(address _factory, address _router) public onlyModerator {
        factory = IUniswapV2Factory( _factory );
        router = IUniswapV2Router02( _router );
    }

    function _unstakeAndSwapLp(address bondAddress, address tokenIn, address tokenOut, uint amount) private returns (uint256) {
        _claimPendingRewards(bondAddress);
        return _token2Token(tokenIn, tokenOut, amount.div(2));
    }

    function _addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin) internal {
            _approveToken(tokenA, address(router), amountADesired);
            _approveToken(tokenB, address(router), amountBDesired);
            router.addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, address(this), deadline);
        }

    /**
    @notice This function is used to swap ERC20 <> ERC20
    @param _FromTokenContractAddress The token address to swap from.
    @param _ToTokenContractAddress The token address to swap to. 
    @param tokens2Trade The amount of tokens to swap
    @return tokenBought The quantity of tokens bought
    */
    function _token2Token(
        address _FromTokenContractAddress,
        address _ToTokenContractAddress,
        uint256 tokens2Trade
    ) internal returns (uint256 tokenBought) {
        if (_FromTokenContractAddress == _ToTokenContractAddress) {
            return tokens2Trade;
        }

        _approveToken(
            _FromTokenContractAddress,
            address(router),
            tokens2Trade
        );

        address pair =
            factory.getPair(
                _FromTokenContractAddress,
                _ToTokenContractAddress
            );
        require(pair != address(0), "No Swap Available");
        address[] memory path = new address[](2);
        path[0] = _FromTokenContractAddress;
        // path[1] = wavaxTokenAddress;
        path[1] = _ToTokenContractAddress;

        tokenBought = router.swapExactTokensForTokens(
            tokens2Trade,
            1,
            path,
            address(this),
            deadline
        )[path.length - 1];

        require(tokenBought > 0, "Error Swapping Tokens 2");

        return tokenBought;
    }

    function _approveToken(address token, address spender) internal {
        IERC20 _token = IERC20(token);
        if (_token.allowance(address(this), spender) > 0) return;
        else {
            _token.safeApprove(spender, type(uint256).max);
        }
    }

    function _approveToken(
        address token,
        address spender,
        uint256 amount
    ) internal {
        IERC20(token).safeApprove(spender, 0);
        IERC20(token).safeApprove(spender, amount);
    }
    
    function _getTokenAmount(address token) private view returns (uint) {
        return IERC20( token ).balanceOf(address(this));
    }

    function _stakeTime() private {
        uint256 amount = time.balanceOf(address(this));
        require(amount > 0, "Not enough Time balance");
        time.approve( address(staking), amount);
        staking.stake(amount, address(this));
    }
    
    function _unstakeMemo(uint amount) private {
        require(amount <= memo.balanceOf(address(this)), "Not enough Memo balance");
        memo.approve( address(staking), amount );
        staking.unstake(amount, true);
    }
    
    function _claimPendingRewards(address bondAddress) private {
        uint claimable = ITimeBondDepository( bondAddress ).pendingPayoutFor( address(this));
        if (claimable > 0) {
            ITimeBondDepository( bondAddress ).redeem(address(this), false);    
        }
    }
}