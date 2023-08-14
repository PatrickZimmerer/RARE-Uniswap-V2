// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFakeUniswapPoolFactory {
    event PoolCreated(
        address indexed tokenA,
        address indexed tokenB,
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
