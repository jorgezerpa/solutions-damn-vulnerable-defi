// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Test, console} from "forge-std/Test.sol";


/**
 * @notice A contract that allows deployers of Gnosis Safe wallets to be rewarded.
 *         Includes an optional authorization mechanism to ensure only expected accounts
 *         are rewarded for certain deployments.
 */
contract WalletDeployer {
    // Addresses of a Safe factory and copy on this chain
    SafeProxyFactory public immutable cook; // PROXY FACTORY 
    address public immutable cpy; // IMPLEMENTATION CONTRACT

    uint256 public constant pay = 1 ether;
    address public immutable chief; // DEPLOYER
    address public immutable gem; // TOKEN

    address public mom; // AUTHORIZER
    address public hat;

    error Boom();

    constructor(address _gem, address _cook, address _cpy, address _chief) {
        gem = _gem; // TOKEN 
        cook = SafeProxyFactory(_cook); // PROXY FACTORY 
        cpy = _cpy; // IMPLEMENTATION CONTRACT 
        chief = _chief; // DEPLOYER
    }

    /**
     * @notice Allows the chief to set an authorizer contract.
     */
    // Can only be called by the chief and AUTHORIZER can be setted once, no more
    // _mom param can not be 0, so it is not an option 
    function rule(address _mom) external {
        if (msg.sender != chief || _mom == address(0) || mom != address(0)) {
            revert Boom();
        }
        mom = _mom;
    }

    /**
     * @notice Allows the caller to deploy a new Safe account and receive a payment in return.
     *         If the authorizer is set, the caller must be authorized to execute the deployment
     */
    // num == saltNonce
    function drop(address aim, bytes memory wat, uint256 num) external returns (bool) {
        // @audit how can user jump over this?
        // I can play with:
        // - the return of can 
        // - try to change the mom address to a malicious contract 
        if (mom != address(0) && !can(msg.sender, aim)) {
            return false;
        }

        // @audit it does create it anyways -> I can try by brute force until I get it -> It is determinisic, I can try it locally without the need to call the contract 
        // (implementation, initializer, saltNonce)
        if (address(cook.createProxyWithNonce(cpy, wat, num)) != aim) {
            return false;
        }

        if (IERC20(gem).balanceOf(address(this)) >= pay) {
            IERC20(gem).transfer(msg.sender, pay);
        }
        return true;
    }

    function can(address u, address a) public view returns (bool y) {
        assembly {
            let m := sload(0)
            if iszero(extcodesize(m)) { stop() }
            let p := mload(0x40)
            mstore(0x40, add(p, 0x44))
            mstore(p, shl(0xe0, 0x4538c4eb))
            mstore(add(p, 0x04), u)
            mstore(add(p, 0x24), a)
            if iszero(staticcall(gas(), m, p, 0x44, p, 0x20)) { stop() }
            y := mload(p)
        }
    }
}
