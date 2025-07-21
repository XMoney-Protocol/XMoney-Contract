// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IXVault
 * @dev Interface for XVault contract that handles fund storage for unregistered XID users
 * @notice This interface defines functions for depositing and managing funds in the vault
 */
interface IXVault {
    /**
     * @notice Deposits native token for a specific username
     * @param username The username to deposit funds for
     * @dev Funds are stored until the user registers their XID
     */
    function depositNativeToken(string memory username) external payable;
    /**
     * @notice Deposits BEP-20 tokens for a specific username
     * @param username The username to deposit funds for
     * @param token The BEP-20 token contract address
     * @param amount The amount of tokens to deposit
     * @dev Funds are stored until the user registers their XID
     */
    function depositToken(string memory username, address token, uint256 amount) external;
    /**
     * @notice Get the native token balance for a username
     * @param username The username to check balance for
     * @return uint256 The native token balance
     */
    function nativeTokenBalances(string memory username) external view returns (uint256);
    /**
     * @notice Get the token balance for a username and specific token
     * @param username The username to check balance for
     * @param token The token contract address
     * @return uint256 The token balance
     */
    function tokenBalances(string memory username, address token) external view returns (uint256);
    /**
     * @notice Batch deposit tokens for multiple usernames
     * @param usernames Array of usernames to deposit for
     * @param amounts Array of amounts to deposit for each username
     * @param token The token contract address
     * @dev Arrays must have the same length
     */
    function batchDepositToken(string[] memory usernames, uint256[] memory amounts, address token) external;
    /**
     * @notice Batch deposit native token for multiple usernames
     * @param usernames Array of usernames to deposit for
     * @param amounts Array of amounts to deposit for each username
     * @dev Arrays must have the same length, msg.value must equal sum of amounts
     */
    function batchDepositNativeToken(string[] memory usernames, uint256[] memory amounts) external payable;
}   
