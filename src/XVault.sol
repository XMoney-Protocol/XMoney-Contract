// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IXID.sol";

/**
 * @title XVault
 * @dev A vault contract for storing funds for unregistered XID users.
 * Users can withdraw their funds after registering their XID.
 * Supports storage and withdrawal of native tokens and ERC20 tokens.
 */
contract XVault is Ownable {
    using SafeERC20 for IERC20;
    /// @notice The XID contract interface
    IXID public xid;
    /// @notice Mapping of username hash to native token balance
    mapping(bytes32 => uint256) public nativeTokenBalances;
    /// @notice Mapping of username hash to token address to token balance
    mapping(bytes32 => mapping(address => uint256)) public tokenBalances;
    /// @notice Fee rate in basis points (1000 = 10%)
    uint256 public feeRate = 1000;
    /// @notice Address that receives the fees
    address public feeReceiver;
    /// @notice Mapping of token address to accumulated fees
    mapping(address => uint256) public accumulatedTokenFees;
    /// @notice Accumulated native token fees
    uint256 public accumulatedNativeTokenFees;

    /// @notice Emitted when native token is deposited for a username
    event NativeTokenDeposited(
        bytes32 indexed usernameHash,
        string username,
        uint256 amount
    );
    /// @notice Emitted when native token is withdrawn by a username owner
    event NativeTokenWithdrawn(
        bytes32 indexed usernameHash,
        string username,
        address to,
        uint256 amount
    );
    /// @notice Emitted when tokens are deposited for a username
    event TokenDeposited(
        bytes32 indexed usernameHash,
        string username,
        address token,
        uint256 amount
    );
    /// @notice Emitted when tokens are withdrawn by a username owner
    event TokenWithdrawn(
        bytes32 indexed usernameHash,
        string username,
        address token,
        address to,
        uint256 amount
    );
    /// @notice Emitted when native token is batch deposited for multiple usernames
    event BatchNativeTokenDeposited(string[] usernames, uint256[] amounts);
    /// @notice Emitted when tokens are batch deposited for multiple usernames
    event BatchTokenDeposited(
        string[] usernames,
        uint256[] amounts,
        address token
    );
    /// @notice Emitted when fee rate is updated
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    /// @notice Emitted when fee receiver is updated
    event FeeReceiverUpdated(address oldReceiver, address newReceiver);
    /// @notice Emitted when XID contract address is updated
    event XidAddressUpdated(address oldXid, address newXid);
    /// @notice Emitted when fees are claimed for a token
    event FeesClaimed(address indexed token, uint256 amount);

    /**
     * @param _xid Address of the XID contract
     * @param _feeReceiver Address that will receive the fees
     */
    constructor(address _xid, address _feeReceiver) Ownable(msg.sender) {
        xid = IXID(_xid);
        feeReceiver = _feeReceiver;
    }

    /**
     * @notice Deposits native token for a specific username
     * @param username The username to deposit for
     */
    function depositNativeToken(string memory username) external payable {
        require(msg.value > 0, "XVault: Amount must be greater than 0");

        bytes32 usernameHash = _usernameHash(username);
        nativeTokenBalances[usernameHash] += msg.value;

        emit NativeTokenDeposited(usernameHash, username, msg.value);
    }

    /**
     * @notice Deposits ERC20 tokens for a specific username
     * @param username The username to deposit for
     * @param token The token address to deposit
     * @param amount The amount of tokens to deposit
     */
    function depositToken(
        string memory username,
        address token,
        uint256 amount
    ) external {
        require(amount > 0, "XVault: Amount must be greater than 0");
        require(token != address(0), "XVault: Invalid token address");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        bytes32 usernameHash = _usernameHash(username);
        tokenBalances[usernameHash][token] += amount;

        emit TokenDeposited(usernameHash, username, token, amount);
    }

    /**
     * @notice Batch deposits native token for multiple usernames
     * @param usernames Array of usernames to deposit for
     * @param amounts Array of amounts to deposit for each username
     */
    function batchDepositNativeToken(
        string[] calldata usernames,
        uint256[] calldata amounts
    ) external payable {
        require(
            usernames.length == amounts.length,
            "XVault: Arrays length mismatch"
        );

        uint256 totalAmount;
        bytes32[] memory usernameHashes = new bytes32[](usernames.length);

        for (uint i = 0; i < amounts.length; ) {
            totalAmount += amounts[i];
            usernameHashes[i] = keccak256(bytes(usernames[i]));
            unchecked {
                ++i;
            }
        }
        require(msg.value == totalAmount, "XVault: Incorrect total amount");

        for (uint i = 0; i < usernames.length; ) {
            nativeTokenBalances[usernameHashes[i]] += amounts[i];
            unchecked {
                ++i;
            }
        }

        emit BatchNativeTokenDeposited(usernames, amounts);
    }

    /**
     * @notice Batch deposits tokens for multiple usernames
     * @param usernames Array of usernames to deposit for
     * @param amounts Array of amounts to deposit for each username
     * @param token The token address to deposit
     */
    function batchDepositToken(
        string[] memory usernames,
        uint256[] memory amounts,
        address token
    ) external {
        require(
            usernames.length == amounts.length,
            "XVault: Arrays length mismatch"
        );
        require(token != address(0), "XVault: Invalid token address");

        uint256 totalAmount = 0;
        bytes32[] memory usernameHashes = new bytes32[](usernames.length);

        for (uint256 i = 0; i < amounts.length; ) {
            require(amounts[i] > 0, "XVault: Amount must be greater than 0");
            totalAmount += amounts[i];
            usernameHashes[i] = _usernameHash(usernames[i]);
            unchecked {
                ++i;
            }
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);

        for (uint256 i = 0; i < usernames.length; ) {
            tokenBalances[usernameHashes[i]][token] += amounts[i];
            unchecked {
                ++i;
            }
        }

        emit BatchTokenDeposited(usernames, amounts, token);
    }

    /**
     * @notice Withdraws all native token and specified tokens for a username
     * @param username The username to withdraw for
     * @param tokens Array of token addresses to withdraw
     */
    function withdrawAll(
        string memory username,
        address[] calldata tokens
    ) external {
        address owner = xid.getAddressByUsername(username);
        require(owner == msg.sender, "XVault: caller is not the XID owner");

        bytes32 usernameHash = _usernameHash(username);

        // Withdraw native token
        uint256 nativeTokenAmount = nativeTokenBalances[usernameHash];
        if (nativeTokenAmount > 0) {
            _withdrawNativeToken(usernameHash, username);
        }

        // Withdraw specified tokens
        for (uint256 i = 0; i < tokens.length; ) {
            uint256 tokenAmount = tokenBalances[usernameHash][tokens[i]];
            if (tokenAmount > 0) {
                _withdrawToken(usernameHash, username, tokens[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Withdraws native token for a specific username
     * @param username The username to withdraw for
     */
    function withdrawNativeToken(string memory username) external {
        address owner = xid.getAddressByUsername(username);
        require(owner == msg.sender, "XVault: Caller is not the XID owner");
        _withdrawNativeToken(_usernameHash(username), username);
    }

    /**
     * @notice Withdraws specific token for a username
     * @param username The username to withdraw for
     * @param token The token address to withdraw
     */
    function withdrawToken(string memory username, address token) external {
        address owner = xid.getAddressByUsername(username);
        require(owner == msg.sender, "XVault: Caller is not the XID owner");
        _withdrawToken(_usernameHash(username), username, token);
    }

    /**
     * @notice Sets a new fee receiver address
     * @param feeReceiver_ The new fee receiver address
     */
    function setFeeReceiver(address feeReceiver_) external onlyOwner {
        address oldReceiver = feeReceiver;
        feeReceiver = feeReceiver_;
        emit FeeReceiverUpdated(oldReceiver, feeReceiver_);
    }

    /**
     * @notice Sets a new fee rate in basis points
     * @param feeRate_ The new fee rate (100 = 1%)
     */
    function setFeeRate(uint256 feeRate_) external onlyOwner {
        uint256 oldRate = feeRate;
        feeRate = feeRate_;
        emit FeeRateUpdated(oldRate, feeRate_);
    }

    /**
     * @notice Updates the XID contract address
     * @dev Only callable by the contract owner
     * @param newXid_ The new XID contract address
     */
    function setXidAddress(address newXid_) external onlyOwner {
        address oldXid = address(xid);
        xid = IXID(newXid_);
        emit XidAddressUpdated(oldXid, newXid_);
    }

    /**
     * @notice Gets the native token balance for a username
     * @param username The username to check
     * @return The native token balance
     */
    function getNativeTokenBalance(
        string memory username
    ) external view returns (uint256) {
        return nativeTokenBalances[_usernameHash(username)];
    }

    /**
     * @notice Gets the token balance for a username
     * @param username The username to check
     * @param token The token address to check
     * @return The token balance
     */
    function getTokenBalance(
        string memory username,
        address token
    ) external view returns (uint256) {
        return tokenBalances[_usernameHash(username)][token];
    }

    /**
     * @notice Internal function to handle native token withdrawal
     * @param usernameHash The hash of the username
     * @param username The username
     * @return netAmount The amount withdrawn after fees
     */
    function _withdrawNativeToken(
        bytes32 usernameHash,
        string memory username
    ) internal returns (uint256 netAmount) {
        uint256 amount = nativeTokenBalances[usernameHash];
        require(amount > 0, "XVault: No native token balance");

        uint256 fee = (amount * feeRate) / 10000;
        netAmount = amount - fee;

        // Reset balance to zero
        nativeTokenBalances[usernameHash] = 0;

        // Transfer net amount to user
        (bool success, ) = payable(msg.sender).call{value: netAmount}("");
        require(success, "XVault: Native token transfer failed");

        // Accumulate native token fees
        if (fee > 0) {
            accumulatedNativeTokenFees += fee;
        }

        emit NativeTokenWithdrawn(usernameHash, username, msg.sender, netAmount);
    }

    /**
     * @notice Internal function to handle token withdrawal
     * @param usernameHash The hash of the username
     * @param username The username
     * @param token The token address
     * @return netAmount The amount withdrawn after fees
     */
    function _withdrawToken(
        bytes32 usernameHash,
        string memory username,
        address token
    ) internal returns (uint256 netAmount) {
        require(token != address(0), "XVault: Invalid token address");
        uint256 amount = tokenBalances[usernameHash][token];
        require(amount > 0, "XVault: No token balance");

        uint256 fee = (amount * feeRate) / 10000;
        netAmount = amount - fee;

        // Reset balance to zero
        tokenBalances[usernameHash][token] = 0;

        // Transfer net amount to user
        IERC20(token).safeTransfer(msg.sender, netAmount);

        // Accumulate ERC20 token fees
        if (fee > 0) {
            accumulatedTokenFees[token] += fee;
        }

        emit TokenWithdrawn(
            usernameHash,
            username,
            token,
            msg.sender,
            netAmount
        );
    }

    /**
     * @notice Hashes a username string
     * @param username The username to hash
     * @return The keccak256 hash of the username
     */
    function _usernameHash(
        string memory username
    ) internal pure returns (bytes32) {
        return keccak256(bytes(username));
    }

    /**
     * @notice Claim accumulated fees for a specific token
     * @dev Only callable by the fee receiver
     * @param token ERC20 token contract address
     */
    function claimTokenFees(address token) external {
        require(
            msg.sender == feeReceiver,
            "XVault: Only fee receiver can claim fees"
        );
        uint256 amount = accumulatedTokenFees[token];
        require(amount > 0, "XVault: No token fees to claim");

        // Reset accumulated fees
        accumulatedTokenFees[token] = 0;

        // Transfer accumulated fees to fee receiver
        IERC20(token).safeTransfer(feeReceiver, amount);

        emit FeesClaimed(token, amount);
    }

    /**
     * @notice Claim accumulated fees for multiple tokens
     * @dev Only callable by the fee receiver
     * @param tokens Array of ERC20 token contract addresses
     */
    function claimMultipleTokenFees(address[] calldata tokens) external {
        require(
            msg.sender == feeReceiver,
            "XVault: Only fee receiver can claim fees"
        );

        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = accumulatedTokenFees[token];

            if (amount > 0) {
                // Reset accumulated fees
                accumulatedTokenFees[token] = 0;

                // Transfer accumulated fees to fee receiver
                IERC20(token).safeTransfer(feeReceiver, amount);

                emit FeesClaimed(token, amount);
            }
        }
    }

    /**
     * @notice Claim accumulated fees for native token
     * @dev Only callable by the fee receiver
     */
    function claimNativeTokenFees() external {
        require(
            msg.sender == feeReceiver,
            "XVault: Only fee receiver can claim fees"
        );
        uint256 amount = accumulatedNativeTokenFees;
        require(amount > 0, "XVault: No native token fees to claim");

        // Reset accumulated fees
        accumulatedNativeTokenFees = 0;

        // Transfer accumulated fees to fee receiver
        (bool success, ) = payable(feeReceiver).call{value: amount}("");
        require(success, "XVault: Native token fee transfer failed");

        emit FeesClaimed(address(0), amount);
    }

    /**
     * @notice Get accumulated fees for a specific token
     * @param token ERC20 token contract address
     * @return uint256 Amount of accumulated fees for the token
     */
    function getAccumulatedTokenFees(
        address token
    ) external view returns (uint256) {
        return accumulatedTokenFees[token];
    }

    /**
     * @notice Get accumulated fees for native token
     * @return uint256 Amount of accumulated fees for native token
     */
    function getAccumulatedNativeTokenFees() external view returns (uint256) {
        return accumulatedNativeTokenFees;
    }

    /// @notice Allows the contract to receive native token
    receive() external payable {}
}
