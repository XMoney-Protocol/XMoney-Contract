// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IXMoney
 * @dev Interface for XMoney contract, defines functions that FeeDistributor needs to call
 * @notice This interface exposes fee management functions for external contracts
 */
interface IXMoney {
    /**
     * @notice Get accumulated native token fees
     * @return uint256 Amount of accumulated native token fees
     */
    function getAccumulatedNativeTokenFees() external view returns (uint256);
    
    /**
     * @notice Get accumulated fees for a specific token
     * @param token BEP-20 token contract address
     * @return uint256 Amount of accumulated token fees
     */
    function getAccumulatedTokenFees(address token) external view returns (uint256);
    
    /**
     * @notice Claim accumulated native token fees
     * @dev Only callable by the fee receiver
     */
    function claimNativeTokenFees() external;
    
    /**
     * @notice Claim accumulated fees for a specific token
     * @param token BEP-20 token contract address
     * @dev Only callable by the fee receiver
     */
    function claimTokenFees(address token) external;
    
    /**
     * @notice Claim accumulated fees for multiple tokens
     * @param tokens Array of BEP-20 token contract addresses
     * @dev Only callable by the fee receiver
     */
    function claimMultipleTokenFees(address[] calldata tokens) external;
} 