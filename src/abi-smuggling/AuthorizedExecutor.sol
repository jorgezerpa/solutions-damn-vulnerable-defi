// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Test, console} from "forge-std/Test.sol";

abstract contract AuthorizedExecutor is ReentrancyGuard {
    using Address for address;

    bool public initialized;

    // action identifier => allowed
    mapping(bytes32 => bool) public permissions;

    error NotAllowed();
    error AlreadyInitialized();

    event Initialized(address who, bytes32[] ids);

    /**
     * @notice Allows first caller to set permissions for a set of action identifiers
     * @param ids array of action identifiers
     */
    function setPermissions(bytes32[] memory ids) external {
        if (initialized) {
            revert AlreadyInitialized();
        }

        for (uint256 i = 0; i < ids.length;) {
            unchecked {
                permissions[ids[i]] = true;
                ++i;
            }
        }
        initialized = true;

        emit Initialized(msg.sender, ids);
    }

    /**
     * @notice Performs an arbitrary function call on a target contract, if the caller is authorized to do so.
     * @param target account where the action will be executed
     * @param actionData abi-encoded calldata to execute on the target
     */
    /*
    mock the abi
        function execute(address target, bytes calldata actionData, uint256 offset, bytes4 selector)
    */
   // function sweepFunds(address receiver, IERC20 token)
   // function withdraw(address token, address recipient, uint256 amount)
    function execute(address target,bytes calldata actionData) external nonReentrant returns (bytes memory) {
        // Read the 4-bytes selector at the beginning of `actionData`
        // @audit Can I mock to make the "selector" one function but the called selector another?
        // @audit can I 
        bytes4 selector;
        // 4 bytes of selector + space for 3 params -> target, actionData offset, action data length -> GRIAL
        uint256 calldataOffset = 4 + 32 * 3; // calldata position where `actionData` begins
        assembly {
            selector := calldataload(calldataOffset) // reads 32 bytes, but typecast to bytes4 aka takes the first 4 bytes 
        }
        console.logBytes(abi.encode(selector));
        // target is invariant -> address(this), sender can not be mocked and selector is fixed...fixed?
        if (!permissions[getActionId(selector, msg.sender, target)]) {
            revert NotAllowed();
        }

        _beforeFunctionCall(target, actionData);
        // @audit whatever is called here, the msg.sender will be this contract 
        return target.functionCall(actionData);
    }

    // the implementation is -> if target is not this contract, then revert 
    function _beforeFunctionCall(address target, bytes memory actionData) internal virtual;

    function getActionId(bytes4 selector, address executor, address target) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(selector, executor, target));
    }
}
