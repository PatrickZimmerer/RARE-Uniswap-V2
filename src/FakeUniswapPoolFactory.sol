// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "./FakeUniswapPool.sol";

contract FakeUniswapPoolFactory {
    address public immutable feeTo;

    mapping(address => mapping(address => address)) public getPool;
    address[] public allPools;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint
    );

    error ZERO_ADDRESS();
    error POOL_ALREADY_EXISTS();
    error IDENTICAL_ADDRESSES();

    constructor(address _feeTo) {
        // set address which will receive fees
        feeTo = _feeTo;
    }

    function createLiquidityPool(
        address tokenA,
        address tokenB,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol
    ) external returns (address pair) {
        // check for identical addresses, already existing pools & zero address
        if (tokenA == tokenB) revert IDENTICAL_ADDRESSES();
        if (tokenA == address(0) || tokenB == address(0)) revert ZERO_ADDRESS();
        if (getPool[tokenA][tokenB] != address(0)) revert POOL_ALREADY_EXISTS();
        // create new pool if passed conditions
        FakeUniswapPool pool = new FakeUniswapPool(
            tokenA,
            tokenB,
            liquidityTokenName,
            liquidityTokenSymbol
        );
        FakeUniswapPool(pool).initialize(tokenA, tokenB);
        // populate mapping in both directions
        getPool[tokenA][tokenB] = pair;
        getPool[tokenB][tokenA] = pair;
        allPools.push(address(pool));
        emit PairCreated(tokenA, tokenB, pair, allPools.length);
    }
}
