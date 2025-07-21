// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IXMoney.sol";

/**
 * @title FeeDistributor
 * @dev Receives fees from XMoney contract and distributes them to two controllers at fixed ratios
 * @notice This contract manages fee distribution with 10% going to controller1 and 90% to controller2
 */
contract FeeDistributor is Ownable {
    /// @notice Controller addresses for fee distribution
    address public controller1; /// @dev Receives 10% of fees
    address public controller2; /// @dev Receives 90% of fees
    
    /// @notice XMoney contract address
    address public xMoney;
    
    /// @notice Distribution ratios in basis points (10000 = 100%)
    uint256 public constant CONTROLLER1_SHARE = 1000; /// @dev 10%
    uint256 public constant CONTROLLER2_SHARE = 9000; /// @dev 90%
    
    /// @notice Events
    event NativeTokenFeeClaimed(address indexed claimer, uint256 amount);
    event TokenFeeClaimed(address indexed claimer, address indexed token, uint256 amount);
    event ControllerUpdated(uint8 controllerIndex, address oldController, address newController);
    event XMoneyUpdated(address oldXMoney, address newXMoney);
    event FeesClaimedFromXMoney(address indexed token, uint256 amount);
    
    /**
     * @notice Constructor to initialize the fee distributor
     * @param _controller1 First controller address (receives 10%)
     * @param _controller2 Second controller address (receives 90%)
     * @param _xMoney XMoney contract address
     */
    constructor(address _controller1, address _controller2, address _xMoney) Ownable(msg.sender) {
        require(_controller1 != address(0), "FeeDistributor: controller1 cannot be zero address");
        require(_controller2 != address(0), "FeeDistributor: controller2 cannot be zero address");
        require(_xMoney != address(0), "FeeDistributor: xMoney cannot be zero address");
        
        controller1 = _controller1;
        controller2 = _controller2;
        xMoney = _xMoney;
    }
    
    /**
     * @notice Update controller address
     * @param controllerIndex Controller index (1 or 2)
     * @param newController New controller address
     * @dev Only callable by contract owner
     */
    function setController(uint8 controllerIndex, address newController) external onlyOwner {
        require(newController != address(0), "FeeDistributor: new controller cannot be zero address");
        
        if (controllerIndex == 1) {
            address oldController = controller1;
            controller1 = newController;
            emit ControllerUpdated(1, oldController, newController);
        } else if (controllerIndex == 2) {
            address oldController = controller2;
            controller2 = newController;
            emit ControllerUpdated(2, oldController, newController);
        } else {
            revert("FeeDistributor: invalid controller index");
        }
    }
    
    /**
     * @notice Set XMoney contract address
     * @param _xMoney New XMoney contract address
     * @dev Only callable by contract owner
     */
    function setXMoney(address _xMoney) external onlyOwner {
        require(_xMoney != address(0), "FeeDistributor: xMoney cannot be zero address");
        address oldXMoney = xMoney;
        xMoney = _xMoney;
        emit XMoneyUpdated(oldXMoney, _xMoney);
    }
    
    /**
     * @notice Claim native token fees from XMoney contract
     * @dev Only callable by controllers or contract owner
     */
    function claimNativeTokenFeesFromXMoney() external {
        // Only allow controllers or contract owner to call this function
        require(
            msg.sender == controller1 || msg.sender == controller2 || msg.sender == owner(),
            "FeeDistributor: only controllers or owner can claim fees from XMoney"
        );
        
        // Ensure XMoney contract address is set
        require(xMoney != address(0), "FeeDistributor: xMoney not set");
        
        // Get accumulated native token fees from XMoney contract
        uint256 nativeTokenFees = IXMoney(xMoney).getAccumulatedNativeTokenFees();
        require(nativeTokenFees > 0, "FeeDistributor: no native token fees to claim from XMoney");
        
        // Call XMoney contract's claimNativeTokenFees function
        IXMoney(xMoney).claimNativeTokenFees();
        
        emit FeesClaimedFromXMoney(address(0), nativeTokenFees);
    }
    
    /**
     * @notice Claim token fees from XMoney contract
     * @param token ERC20 token contract address
     * @dev Only callable by controllers or contract owner
     */
    function claimTokenFeesFromXMoney(address token) external {
        // Only allow controllers or contract owner to call this function
        require(
            msg.sender == controller1 || msg.sender == controller2 || msg.sender == owner(),
            "FeeDistributor: only controllers or owner can claim fees from XMoney"
        );
        
        // Ensure XMoney contract address is set
        require(xMoney != address(0), "FeeDistributor: xMoney not set");
        
        // Get accumulated token fees from XMoney contract
        uint256 tokenFees = IXMoney(xMoney).getAccumulatedTokenFees(token);
        require(tokenFees > 0, "FeeDistributor: no token fees to claim from XMoney");
        
        // Call XMoney contract's claimTokenFees function
        IXMoney(xMoney).claimTokenFees(token);
        
        emit FeesClaimedFromXMoney(token, tokenFees);
    }
    
    /**
     * @notice Claim multiple token fees from XMoney contract
     * @param tokens Array of ERC20 token contract addresses
     * @dev Only callable by controllers or contract owner
     */
    function claimMultipleTokenFeesFromXMoney(address[] calldata tokens) external {
        // Only allow controllers or contract owner to call this function
        require(
            msg.sender == controller1 || msg.sender == controller2 || msg.sender == owner(),
            "FeeDistributor: only controllers or owner can claim fees from XMoney"
        );
        
        // Ensure XMoney contract address is set
        require(xMoney != address(0), "FeeDistributor: xMoney not set");
        
        // Call XMoney contract's claimMultipleTokenFees function
        IXMoney(xMoney).claimMultipleTokenFees(tokens);
        
        for (uint i = 0; i < tokens.length; i++) {
            emit FeesClaimedFromXMoney(tokens[i], 0); // We don't know the exact amount, so record as 0
        }
    }
    
    /**
     * @notice Claim native token fees from this contract
     * @dev Only callable by controllers, distributes fees according to their share
     */
    function claimNativeTokenFees() external {
        require(
            msg.sender == controller1 || msg.sender == controller2,
            "FeeDistributor: only controllers can claim fees"
        );
        
        uint256 balance = address(this).balance;
        require(balance > 0, "FeeDistributor: no native token to claim");
        
        uint256 amount;
        if (msg.sender == controller1) {
            amount = (balance * CONTROLLER1_SHARE) / 10000;
        } else {
            amount = (balance * CONTROLLER2_SHARE) / 10000;
        }
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "FeeDistributor: Native token transfer failed");
        
        emit NativeTokenFeeClaimed(msg.sender, amount);
    }
    
    /**
     * @notice Claim token fees from this contract
     * @param token ERC20 token contract address
     * @dev Only callable by controllers, distributes fees according to their share
     */
    function claimTokenFees(address token) external {
        require(
            msg.sender == controller1 || msg.sender == controller2,
            "FeeDistributor: only controllers can claim fees"
        );
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "FeeDistributor: no tokens to claim");
        
        uint256 amount;
        if (msg.sender == controller1) {
            amount = (balance * CONTROLLER1_SHARE) / 10000;
        } else {
            amount = (balance * CONTROLLER2_SHARE) / 10000;
        }
        
        IERC20(token).transfer(msg.sender, amount);
        
        emit TokenFeeClaimed(msg.sender, token, amount);
    }
    
    /**
     * @notice Allow contract to receive native token
     */
    receive() external payable {}
} 