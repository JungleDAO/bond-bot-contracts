// SPDX-License-Identifier: GPL-3.

import "./interfaces/IERC20.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IZapin.sol";
import "./interfaces/ITimeBondDepository.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IWMEMO.sol";
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

    IUniswapV2Factory private constant sushiFactory =
        IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);

    IUniswapV2Router02 private constant sushiRouter =
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    address private constant wavaxTokenAddress =
        address(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    uint256 private constant deadline =
        0xf000000000000000000000000000000000000000000000000000000000000000;
    
    address private owner;
    address private moderator;
    IUniswapV2Factory private factory;
    IUniswapV2Router02 private router;
    
    IERC20 private constant time = IERC20(0xb54f16fB19478766A268F172C9480f8da1a7c9C3);
    IERC20 private constant memo = IERC20(0x136Acd46C134E8269052c62A67042D6bDeDde3C9);
    IERC20 private constant mim = IERC20(0x130966628846BFd36ff31a822705796e8cb8C18D);
    IWMEMO private constant wmemo = IWMEMO(0x0da67235dD5787D67955420C84ca1cEcd4E5Bb3b);

    IStaking private constant staking = IStaking(0x4456B87Af11e87E329AB7d7C7A246ed1aC2168B9);
    
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
    
    function bondLp(
        address bondAddress, 
        address lptoken, 
        address tokenA, 
        address tokenB, 
        uint amount, 
        uint256 maxPrice, 
        bool isSushi,
        bool iswMemo
        ) public onlyOwner { 

            if (iswMemo) {
                _wrapMemo(amount);
                amount = IERC20( tokenA ).balanceOf(address(this)); 
            } else {
                _unstakeMemo(amount);
            }

            IUniswapV2Router02 mainRouter = router;
            IUniswapV2Factory mainFactory = factory;

            if (isSushi) {
                mainRouter = sushiRouter;
                mainFactory = sushiFactory;
            }

            _claimPendingRewards(bondAddress);
            uint256 amountA = amount.div(2);
            uint256 amountB = _token2Token(tokenA, tokenB, amount.div(2), mainRouter, mainFactory);
            _addLiquidity(tokenB, tokenA, amountB, amountA, mainRouter);
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
    
    function bond(address bondAddress, uint256 amount, address tokenIn, address tokenOut, uint256 maxPrice, bool iswEth, bool isSushi) public onlyOwner {
        _unstakeMemo(amount);
        require(time.balanceOf(address(this)) == amount);
        _claimPendingRewards(bondAddress);
        uint256 tokenBought;
        IUniswapV2Router02 mainRouter = router;
        IUniswapV2Factory mainFactory = factory;
        if (isSushi) {
            mainRouter = sushiRouter;
            mainFactory = sushiFactory;
        }
        if (iswEth) {
            tokenBought = _token2TokenwAvax(tokenIn, tokenOut, amount, mainRouter, mainFactory);
        } else {
            tokenBought = _token2Token(tokenIn, tokenOut, amount, mainRouter, mainFactory);
        }

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

    function _addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, IUniswapV2Router02 mainRouter) internal {
            _approveToken(tokenA, address(mainRouter), amountADesired);
            _approveToken(tokenB, address(mainRouter), amountBDesired);
            uint256 minAmountA = amountADesired.mul(99) / 100;
            uint256 minAmountB = amountBDesired.mul(99) / 100;
            mainRouter.addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, minAmountA, minAmountB, address(this), deadline);
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
        uint256 tokens2Trade,
        IUniswapV2Router02 mainRouter,
        IUniswapV2Factory mainFactory
    ) internal returns (uint256 tokenBought) {
        if (_FromTokenContractAddress == _ToTokenContractAddress) {
            return tokens2Trade;
        }

        _approveToken(
            _FromTokenContractAddress,
            address(mainRouter),
            tokens2Trade
        );

        address pair =
            mainFactory.getPair(
                _FromTokenContractAddress,
                _ToTokenContractAddress
            );
        require(pair != address(0), "No Swap Available");
        address[] memory path = new address[](2);
        path[0] = _FromTokenContractAddress;
        path[1] = _ToTokenContractAddress;

        tokenBought = mainRouter.swapExactTokensForTokens(
            tokens2Trade,
            1,
            path,
            address(this),
            deadline
        )[path.length - 1];

        require(tokenBought > 0, "Error Swapping Tokens 2");

        return tokenBought;
    }

    function _token2TokenwAvax(
        address _FromTokenContractAddress,
        address _ToTokenContractAddress,
        uint256 tokens2Trade,
        IUniswapV2Router02 mainRouter,
        IUniswapV2Factory mainFactory
    ) internal returns (uint256 tokenBought) {
        if (_FromTokenContractAddress == _ToTokenContractAddress) {
            return tokens2Trade;
        }

        _approveToken(
            _FromTokenContractAddress,
            address(mainRouter),
            tokens2Trade
        );

        address pair =
            mainFactory.getPair(
                _FromTokenContractAddress,
                _ToTokenContractAddress
            );
        require(pair != address(0), "No Swap Available");
        address[] memory path = new address[](3);
        path[0] = _FromTokenContractAddress;
        path[1] = wavaxTokenAddress;
        path[2] = _ToTokenContractAddress;

        tokenBought = mainRouter.swapExactTokensForTokens(
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

    function _wrapMemo(uint amount) private {
        require(amount > 0, "Not enough Memo balance to wrap");
        memo.approve(address(wmemo), amount);
        wmemo.wrap(amount);
    }
    
    function _claimPendingRewards(address bondAddress) private {
        uint claimable = ITimeBondDepository( bondAddress ).pendingPayoutFor( address(this));
        if (claimable > 0) {
            ITimeBondDepository( bondAddress ).redeem(address(this), true);    
        }
    }
}