## Direct transfers of underlying tokens to the vault contract cause flash loans to halt

The `flashLoan` function in `UnstoppableVault.sol` has a check to ensures that the balance of the underlying token matches the total value of all shares in circulation:

```
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();
```

However, if a user directly transfers tokens to the vault contract without using the deposit function, the vault's asset balance increases while the totalSupply of shares remains unchanged. This throws off the 1:1 ratio, causing the `convertToShares(totalSupply) != balanceBefore` check to always revert, effectively halting all flash loans. Even a small amount of tokens transferred this way can cause the issue.

### Recommended mitigation

To fix this, it's recommended to replace the use of `asset.balanceOf(address(this))` (used in `totalAssets`) with a new storage variable. This variable would be incremented only by the deposit function, accurately tracking the amount of assets that have been deposited through the official channel. This way, the protocol can reliably check the balance without being affected by direct token transfers.
Additionally, could be considered to implement a function that allows to withdraw the delta between the stored underlaying assets and the real balance. 

### PoC
```solidity
    function test_unstoppable() 
        public 
        checkSolvedByPlayer 
    {
        // transfer dust directly to the vault will halt the flashloan functionality
        token.transfer(address(vault), 1);
    }
```