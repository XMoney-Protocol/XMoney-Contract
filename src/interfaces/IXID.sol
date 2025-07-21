// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IXID
 * @dev Interface for XID contract that manages username to address mappings
 * @notice This interface defines functions for XID username registration and lookup
 */
interface IXID {
    /**
     * @notice Get the address associated with a username
     * @param username The username to look up
     * @return The address that owns the username, or address(0) if not found
     * @dev Returns zero address if username is not registered
     */
    function getAddressByUsername(string memory username) external view returns (address);

    /**
     * @notice Get the username associated with an address
     * @param user The address to look up
     * @return The username owned by the address, or empty string if not found
     * @dev Returns empty string if address has no registered username
     */
    function getUsernameByAddress(address user) external view returns (string memory);

    /**
     * @notice Check if a registration is valid
     * @param tokenId The token ID to check
     * @return True if the registration is valid, false otherwise
     * @dev Used to verify if a specific XID token is still valid
     */
    function isRegistrationValid(uint256 tokenId) external view returns (bool);
} 