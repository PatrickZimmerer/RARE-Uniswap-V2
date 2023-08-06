// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IUniswapV2Factory {
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        address pool,
        uint256
    );

    function getPool(
        address tokenA,
        address tokenB
    ) external view returns (address pool);

    function allPools(uint256) external view returns (address pool);

    function fee() external view returns (uint8 fee);

    function allPoolsLength() external view returns (uint256);

    function createLiquidityPool(
        address tokenA,
        address tokenB
    ) external returns (address pool);
}
