// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "safe-smart-account/contracts/proxies/SafeProxy.sol";
import {IProxyCreationCallback} from "safe-smart-account/contracts/proxies/IProxyCreationCallback.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @notice A registry for Safe multisig wallets.
 *         When known beneficiaries deploy and register their wallets, the registry awards tokens to the wallet.
 * @dev The registry has embedded verifications to ensure only legitimate Safe wallets are stored.
 */
contract WalletRegistry is IProxyCreationCallback, Ownable {
    uint256 private constant EXPECTED_OWNERS_COUNT = 1; // @audit not using multiple owners?
    uint256 private constant EXPECTED_THRESHOLD = 1;
    uint256 private constant PAYMENT_AMOUNT = 10e18;

    address public immutable singletonCopy; // safe singleton
    address public immutable walletFactory; // safe proxy factory
    IERC20 public immutable token;

    mapping(address => bool) public beneficiaries;

    // owner => wallet
    mapping(address => address) public wallets;

    error NotEnoughFunds();
    error CallerNotFactory();
    error FakeSingletonCopy();
    error InvalidInitialization();
    error InvalidThreshold(uint256 threshold);
    error InvalidOwnersCount(uint256 count);
    error OwnerIsNotABeneficiary();
    error InvalidFallbackManager(address fallbackManager);

    constructor(
        address singletonCopyAddress,
        address walletFactoryAddress,
        address tokenAddress,
        address[] memory initialBeneficiaries
    ) {
        _initializeOwner(msg.sender);

        singletonCopy = singletonCopyAddress;
        walletFactory = walletFactoryAddress;
        token = IERC20(tokenAddress);

        for (uint256 i = 0; i < initialBeneficiaries.length; ++i) {
            unchecked {
                beneficiaries[initialBeneficiaries[i]] = true;
            }
        }
    }

    function addBeneficiary(address beneficiary) external onlyOwner {
        beneficiaries[beneficiary] = true;
    }

    /**
     * @notice Function executed when user creates a Safe wallet via SafeProxyFactory::createProxyWithCallback
     *          setting the registry's address as the callback.
     */
    function proxyCreated(SafeProxy proxy, address singleton, bytes calldata initializer, uint256) external override {
        if (token.balanceOf(address(this)) < PAYMENT_AMOUNT) {
            // fail early
            revert NotEnoughFunds();
        }

        address payable walletAddress = payable(proxy);

        // Ensure correct factory and copy
        if (msg.sender != walletFactory) { // should be called from the factory on reateProxyWithCallback function (this is the callback)
            revert CallerNotFactory();
        }

        if (singleton != singletonCopy) { // should use the specified safe contract for logic 
            revert FakeSingletonCopy();
        }

        // Ensure initial calldata was a call to `Safe::setup`
        if (bytes4(initializer[:4]) != Safe.setup.selector) {
            revert InvalidInitialization();
        }

        // Ensure wallet initialization is the expected
        uint256 threshold = Safe(walletAddress).getThreshold();
        if (threshold != EXPECTED_THRESHOLD) { // 1
            revert InvalidThreshold(threshold);
        }

        address[] memory owners = Safe(walletAddress).getOwners();
        if (owners.length != EXPECTED_OWNERS_COUNT) { // 1
            revert InvalidOwnersCount(owners.length);
        }

        // Ensure the owner is a registered beneficiary
        address walletOwner;
        unchecked {
            walletOwner = owners[0];
        }

        // @audit@PAV
        // -> deploy a safe wallet with a beneficiary in owners list
        // -> but on setup function -> add malicious logic -> take funds to recovery address -> how?: moduleManager (allowance) or executor 
        if (!beneficiaries[walletOwner]) {
            revert OwnerIsNotABeneficiary();
        }

        address fallbackManager = _getFallbackManager(walletAddress);
        if (fallbackManager != address(0)) { // no fallback manager @audit try to call a non-existant function to see what happens
            revert InvalidFallbackManager(fallbackManager);
        }

        // Remove owner as beneficiary
        beneficiaries[walletOwner] = false;

        // Register the wallet under the owner's address
        wallets[walletOwner] = walletAddress;

        // Pay tokens to the newly created wallet
        SafeTransferLib.safeTransfer(address(token), walletAddress, PAYMENT_AMOUNT);
    }

    function _getFallbackManager(address payable wallet) private view returns (address) {
        return abi.decode(
            Safe(wallet).getStorageAt(uint256(keccak256("fallback_manager.handler.address")), 0x20), (address)
        );
    }
}
