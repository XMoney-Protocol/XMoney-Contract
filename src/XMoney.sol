// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IXID.sol";
import "./interfaces/IXVault.sol";

/**
 * @title XMoney
 * @dev Handles XID-based transfer functionality, supporting single and batch transfers of BNB and ERC20 tokens
 * If the recipient hasn't registered an XID, funds will be stored in XVault contract for claiming
 * Direct transfers incur a fee, vault deposits are fee-free
 */
contract XMoney is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    /// @notice XID contract interface instance
    IXID public xid;
    /// @notice Vault contract instance for fund storage
    IXVault public vault;
    /// @notice Fee recipient address
    address public feeReceiver;
    /// @notice Direct transfer fee rate (1% = 100 basis points)
    uint256 public feeRate = 100;
    /// @notice Maximum allowed fee rate (3% = 300 basis points)
    uint256 public constant MAX_FEE_RATE = 300;

    /// @notice Emitted when BNB is transferred from `from` to recipient with username `toUsername`.
    event NativeTokenTransferred(
        address indexed from,
        string indexed toUsername,
        uint256 amount,
        uint256 fee
    );

    /// @notice Emitted when ERC20 `token` is transferred from `from` to recipient with username `toUsername`.
    event TokenTransferred(
        address indexed from,
        string indexed toUsername,
        address token,
        uint256 amount,
        uint256 fee
    );

    /// @notice Emitted when BNB is batch transferred from `from` to multiple recipients.
    event BatchNativeTokenTransferred(
        address indexed from,
        string[] toUsernames,
        address[] toAddresses,
        uint256 totalVaultAmount,
        uint256 totalDirectAmount,
        uint256 totalFee
    );

    /// @notice Emitted when ERC20 `token` is batch transferred from `from` to multiple recipients.
    event BatchTokenTransferred(
        address indexed from,
        address indexed token,
        string[] toUsernames,
        address[] toAddresses,
        uint256 totalVaultAmount,
        uint256 totalDirectAmount,
        uint256 totalFee
    );

    /// @notice Emitted when the fee rate is updated.
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when the fee recipient address is updated.
    event FeeReceiverUpdated(address oldReceiver, address newReceiver);

    /// @notice Emitted when the XID contract address is updated.
    event XidAddressUpdated(address oldXid, address newXid);

    /// @notice Emitted when the XVault contract address is updated.
    event XVaultAddressUpdated(address oldVault, address newVault);

    /// @notice Emitted when fees are claimed.
    event FeesClaimed(address indexed token, uint256 amount);

    /// @notice Mapping to track accumulated fees for ERC20 tokens
    mapping(address => uint256) public accumulatedTokenFees;

    /// @notice Mapping to track accumulated fees for BNB
    uint256 public accumulatedNativeTokenFees;

    /**
     * @notice Constructor
     * @param _xid XID contract address
     * @param _vault XVault contract address
     * @param _feeReceiver Fee recipient address
     */
    constructor(
        address _xid,
        address _vault,
        address _feeReceiver
    ) Ownable(msg.sender) {
        xid = IXID(_xid);
        vault = IXVault(_vault);
        feeReceiver = _feeReceiver;
    }

    /**
     * @notice Transfer BNB to a specified XID user
     * @dev If the recipient has registered an XID, a fee is deducted before transferring; if not, the full amount is deposited into vault
     * @param toUsername Recipient's XID username
     */
    function transferNativeToken(
        string memory toUsername
    ) external payable nonReentrant {
        require(msg.value > 0, "XMoney: Amount must be greater than 0");

        // Get the recipient's address
        address recipient = xid.getAddressByUsername(toUsername);

        if (recipient != address(0)) {
            // If the recipient has registered an XID, direct transfer with a fee
            unchecked {
                // Direct transfer with a fee
                uint256 fee = (msg.value * feeRate) / 10000;
                uint256 transferAmount = msg.value - fee;

                // Accumulate BNB fees
                if (fee > 0) {
                    accumulatedNativeTokenFees += fee;
                }

                // Use a low-level call to transfer BNB directly
                (bool success, ) = payable(recipient).call{
                    value: transferAmount
                }("");
                require(success, "XMoney: BNB transfer failed");

                emit NativeTokenTransferred(
                    msg.sender,
                    toUsername,
                    transferAmount,
                    fee
                );
            }
        } else {
            // If the recipient has not registered an XID, deposit BNB into the vault contract
            vault.depositNativeToken{value: msg.value}(toUsername);
            emit NativeTokenTransferred(msg.sender, toUsername, msg.value, 0);
        }
    }

    /**
     * @notice Transfer ERC20 tokens to a specified XID user
     * @dev If the recipient has registered an XID, a fee is deducted before transferring; if not, the full amount is deposited into vault
     * @param toUsername Recipient's XID username
     * @param amount Transfer amount
     * @param token ERC20 token contract address
     */
    function transferToken(
        string memory toUsername,
        uint256 amount,
        address token
    ) external nonReentrant {
        // Verify that the transfer amount is greater than 0
        require(amount > 0, "XMoney: Amount must be greater than 0");

        // Transfer tokens into the contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Get the recipient's address
        address recipient = xid.getAddressByUsername(toUsername);

        if (recipient != address(0)) {
            // If the recipient has registered an XID, direct transfer with a fee
            unchecked {
                uint256 fee = (amount * feeRate) / 10000;
                uint256 transferAmount = amount - fee;

                // Accumulate ERC20 token fees
                if (fee > 0) {
                    accumulatedTokenFees[token] += fee;
                }

                // Transfer to the recipient
                IERC20(token).safeTransfer(recipient, transferAmount);

                emit TokenTransferred(
                    msg.sender,
                    toUsername,
                    token,
                    transferAmount,
                    fee
                );
            }
        } else {
            // If the recipient has not registered an XID, deposit tokens into the vault
            IERC20(token).forceApprove(address(vault), amount);
            vault.depositToken(toUsername, token, amount);
            emit TokenTransferred(msg.sender, toUsername, token, amount, 0);
        }
    }

    /**
     * @notice Batch transfer BNB to multiple XID users (handled separately for registered and unregistered users)
     * @dev Charges a fee for registered users, deposits full amount into vault for unregistered users
     * @param toUsernames Array of unregistered XID usernames
     * @param vaultAmounts Array of amounts deposited to vault (unregistered users)
     * @param toAddresses Array of registered user addresses
     * @param directAmounts Array of amounts directly transferred (registered users)
     */
    function batchTransferNativeToken(
        string[] calldata toUsernames,
        uint256[] calldata vaultAmounts, // Amounts to be deposited into the vault (unregistered users)
        address[] calldata toAddresses,
        uint256[] calldata directAmounts // Amounts for direct transfer (registered users)
    ) external payable nonReentrant {
        require(
            toUsernames.length == vaultAmounts.length,
            "XMoney: Vault arrays length mismatch"
        );
        require(
            toAddresses.length == directAmounts.length,
            "XMoney: Direct arrays length mismatch"
        );
        require(
            toUsernames.length + toAddresses.length > 0,
            "XMoney: Empty arrays"
        );

        (uint256 vaultTotal, uint256 directTotal) = _sumArrays(
            vaultAmounts,
            directAmounts
        );

        require(
            msg.value == vaultTotal + directTotal,
            "XMoney: Incorrect total amount"
        );

        // Calculate the fee for registered addresses
        uint256 totalFee = (directTotal * feeRate) / 10000;

        // Accumulate BNB fees
        if (totalFee > 0) {
            accumulatedNativeTokenFees += totalFee;
        }

        // Process direct transfers
        _processDirectNativeTokenTransfers(toAddresses, directAmounts);

        // Handle deposits for unregistered users (no fee charged)
        if (toUsernames.length > 0) {
            vault.batchDepositNativeToken{value: vaultTotal}(toUsernames, vaultAmounts);
        }

        emit BatchNativeTokenTransferred(
            msg.sender,
            toUsernames,
            toAddresses,
            vaultTotal,
            directTotal,
            totalFee
        );
    }

    /**
     * @notice Batch transfer ERC20 tokens to multiple XID users (handled separately for registered and unregistered users)
     * @dev Charges fee for registered users, deposits full amount into vault for unregistered users
     * @param toUsernames Array of unregistered XID usernames
     * @param vaultAmounts Array of amounts deposited to vault (unregistered users)
     * @param toAddresses Array of registered user addresses
     * @param directAmounts Array of amounts directly transferred (registered users)
     * @param token ERC20 token contract address
     */
    function batchTransferToken(
        string[] calldata toUsernames,
        uint256[] calldata vaultAmounts,
        address[] calldata toAddresses,
        uint256[] calldata directAmounts,
        address token
    ) external nonReentrant {
        require(
            toUsernames.length == vaultAmounts.length,
            "XMoney: Vault arrays length mismatch"
        );
        require(
            toAddresses.length == directAmounts.length,
            "XMoney: Direct arrays length mismatch"
        );
        require(
            toUsernames.length + toAddresses.length > 0,
            "XMoney: Empty arrays"
        );

        (uint256 vaultTotal, uint256 directTotal) = _sumArrays(
            vaultAmounts,
            directAmounts
        );
        uint256 totalAmount = vaultTotal + directTotal;
        uint256 totalFee = (directTotal * feeRate) / 10000;

        // Transfer tokens from sender to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);

        // Accumulate ERC20 token fees
        if (totalFee > 0) {
            accumulatedTokenFees[token] += totalFee;
        }

        // Process direct token transfers
        _processDirectTokenTransfers(toAddresses, directAmounts, token);

        // Process vault deposits
        if (toUsernames.length > 0) {
            IERC20(token).forceApprove(address(vault), vaultTotal);
            vault.batchDepositToken(toUsernames, vaultAmounts, token);
        }

        emit BatchTokenTransferred(
            msg.sender,
            token,
            toUsernames,
            toAddresses,
            vaultTotal,
            directTotal,
            totalFee
        );
    }

    /// @dev Internal function to process direct BNB transfers
    function _processDirectNativeTokenTransfers(
        address[] calldata toAddresses,
        uint256[] calldata directAmounts
    ) internal {
        uint256 _feeRate = feeRate; // Cache fee rate to save gas
        for (uint256 i = 0; i < toAddresses.length; ) {
            require(toAddresses[i] != address(0), "XMoney: Invalid address");
            uint256 adjustedAmount = (directAmounts[i] * (10000 - _feeRate)) /
                10000;
            (bool success, ) = payable(toAddresses[i]).call{
                value: adjustedAmount
            }("");
            require(success, "XMoney: BNB transfer failed");
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Internal function to process direct transfers
    function _processDirectTokenTransfers(
        address[] calldata toAddresses,
        uint256[] calldata directAmounts,
        address token
    ) internal {
        uint256 _feeRate = feeRate; // Cache fee rate to save gas
        for (uint256 i = 0; i < toAddresses.length; ) {
            require(toAddresses[i] != address(0), "XMoney: Invalid address");
            uint256 adjustedAmount = (directAmounts[i] * (10000 - _feeRate)) /
                10000;
            IERC20(token).safeTransfer(toAddresses[i], adjustedAmount);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Internal function to calculate the sum of arrays
    function _sumArrays(
        uint256[] calldata arr1,
        uint256[] calldata arr2
    ) internal pure returns (uint256 sum1, uint256 sum2) {
        assembly {
            // Calculate the sum of the first array
            let length := arr1.length
            let ptr := arr1.offset
            for {
                let i := 0
            } lt(i, length) {
                i := add(i, 1)
            } {
                sum1 := add(sum1, calldataload(add(ptr, mul(i, 0x20))))
            }

            // Calculate the sum of the second array
            length := arr2.length
            ptr := arr2.offset
            for {
                let i := 0
            } lt(i, length) {
                i := add(i, 1)
            } {
                sum2 := add(sum2, calldataload(add(ptr, mul(i, 0x20))))
            }
        }
    }

    /**
     * @notice Modify the fee rate
     * @dev Can only be called by the contract owner
     * @param newRate_ The new fee rate (in basis points)
     */
    function setFeeRate(uint256 newRate_) external onlyOwner {
        require(newRate_ <= MAX_FEE_RATE, "XMoney: Fee rate exceeds maximum");
        uint256 oldRate = feeRate;
        feeRate = newRate_;
        emit FeeRateUpdated(oldRate, newRate_);
    }

    /**
     * @notice Updates the fee receiver address
     * @dev Only callable by the contract owner
     * @param newReceiver_ The new address to receive fees
     */
    function setFeeReceiver(address newReceiver_) external onlyOwner {
        address oldReceiver = feeReceiver;
        feeReceiver = newReceiver_;
        emit FeeReceiverUpdated(oldReceiver, newReceiver_);
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
     * @notice Updates the vault contract address
     * @dev Only callable by the contract owner
     * @param newVault_ The new vault contract address
     */
    function setXVaultAddress(address newVault_) external onlyOwner {
        address oldVault = address(vault);
        vault = IXVault(newVault_);
        emit XVaultAddressUpdated(oldVault, newVault_);
    }

    /**
     * @notice Claim accumulated fees for a specific token
     * @dev Only callable by the fee receiver
     * @param token ERC20 token contract address
     */
    function claimTokenFees(address token) external {
        require(
            msg.sender == feeReceiver,
            "XMoney: Only fee receiver can claim fees"
        );
        uint256 amount = accumulatedTokenFees[token];
        require(amount > 0, "XMoney: No token fees to claim");

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
            "XMoney: Only fee receiver can claim fees"
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
     * @notice Claim accumulated fees for BNB
     * @dev Only callable by the fee receiver
     */
    function claimNativeTokenFees() external {
        require(
            msg.sender == feeReceiver,
            "XMoney: Only fee receiver can claim fees"
        );
        uint256 amount = accumulatedNativeTokenFees;
        require(amount > 0, "XMoney: No BNB fees to claim");

        // Reset accumulated fees
        accumulatedNativeTokenFees = 0;

        // Transfer accumulated fees to fee receiver
        (bool success, ) = payable(feeReceiver).call{value: amount}("");
        require(success, "XMoney: BNB fee transfer failed");

        emit FeesClaimed(address(0), amount);
    }

    /**
     * @notice Get accumulated fees for a specific token
     * @dev Only callable by anyone
     * @param token ERC20 token contract address
     * @return uint256 Amount of accumulated fees for the token
     */
    function getAccumulatedTokenFees(
        address token
    ) external view returns (uint256) {
        return accumulatedTokenFees[token];
    }

    /**
     * @notice Get accumulated fees for BNB
     * @dev Only callable by anyone
     * @return uint256 Amount of accumulated fees for BNB
     */
    function getAccumulatedNativeTokenFees() external view returns (uint256) {
        return accumulatedNativeTokenFees;
    }

    /// @notice Allows the contract to receive BNB
    receive() external payable {}
}
