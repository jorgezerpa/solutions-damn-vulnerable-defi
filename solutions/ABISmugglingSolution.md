## The `execute` function uses a hardcoded offset to read a specific position of the calldata, allowing an attacker to bypass authorization logic and execute non-permitted functions.

The `execute` function aims to verify user permissions before executing an arbitrary function call. It does so by retrieving a function selector from the call data, which is then used in a permission check.

The function uses inline assembly to load the selector from a specific, hardcoded offset within the calldata: `uint256 calldataOffset = 4 + 32 * 3;`. This offset is calculated based on the expected structure of the `execute` function's arguments: 4 bytes for the function selector, 32 bytes for the `target` address, and 32 bytes each for the offset and length of the dynamic `actionData` parameter. On this position, is supposed to be the selector of the function to be called.

An attacker can exploit this fixed offset by crafting a malicious transaction where they "smuggle" a whitelisted function selector into the expected position, effectively lying to the authorization check. The forged selector, (one that the attacker is authorized to use like `withdraw` function), is placed at the `calldataOffset` to satisfy the `permissions[getActionId(...)]` check.

After the check passes, the contract proceeds to call `target.functionCall(actionData)` so the unauthorized function call in `actionData` (`sweepFunds` in this case) is executed.

## PoC
```solidity
    function test_abiSmuggling() public 
    checkSolvedByPlayer 
    {
        bytes memory sweepCall = abi.encodeWithSelector(vault.sweepFunds.selector, player, address(token));
        bytes memory executeCall = abi.encodeWithSelector(
            vault.execute.selector, 
            address(vault), // 32 bytes x1
            sweepCall, // 32 bytes x2
            // ---- THE ATTACK HERE ----
            uint256(1), //  32 bytes x3
            vault.withdraw.selector // This is a function that player is allowed to call, but the real actionData has another parameter
        );
        address(vault).call(executeCall);
        token.transfer(recovery, token.balanceOf(player));
    }
```