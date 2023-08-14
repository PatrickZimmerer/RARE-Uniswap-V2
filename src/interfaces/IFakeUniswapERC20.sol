// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

interface IFakeUniswapERC20 is IERC20, IERC20Metadata {
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets0,
        uint256 assets1,
        uint256 shares
    );

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets0,
        uint256 assets1,
        uint256 shares
    );

    function initialize(
        address token0_,
        address token1_,
        uint8 flashLoanFee_
    ) external;

    function assetA() external view returns (address assetTokenAddress);

    function assetB() external view returns (address assetTokenAddress);

    function totalAssets()
        external
        view
        returns (uint128 totalManagedAssets0, uint128 totalManagedAssets1);

    function convertToShares(
        uint256 assets0,
        uint256 assets1
    ) external view returns (uint256 shares);

    function convertToAssets(
        uint256 shares
    ) external view returns (uint256 assets0, uint256 assets1);

    function maxDeposit(
        address receiver
    ) external view returns (uint256 maxAssets0, uint256 maxAssets1);

    function previewDeposit(
        uint256 assets0,
        uint256 assets1
    ) external view returns (uint256 shares);

    function deposit(
        uint256 assets0,
        uint256 assets1,
        address receiver
    ) external returns (uint256 shares);

    function maxRedeem(address owner) external view returns (uint256 maxShares);

    function previewRedeem(
        uint256 shares
    ) external view returns (uint256 assets0, uint256 assets1);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets0, uint256 assets1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address receiver
    ) external;
}
