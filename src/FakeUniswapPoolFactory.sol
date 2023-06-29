// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "./FakeUniswapLPToken.sol";

contract FakeUniswapPoolFactory {
    address public immutable feeTo;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint
    );

    constructor(address _feeTo) {
        // set address which will receive fees
        feeTo = _feeTo;
    }

    function createLiquidityPool(
        address tokenA,
        address tokenB
    ) external returns (address pair) {}
}
