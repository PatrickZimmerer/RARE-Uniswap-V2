// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IUniswapV2Factory.sol";
import "./FakeUniswapPool.sol";

/**
 * @title FlashLoanReceiver
 * @author Patrick Zimmerer
 * @notice A simple FlashLoanReceiver contract that is just used for testing purposes
 */

contract FakeUniswapPoolFactory is IUniswapV2Factory {
    uint8 public fee;
    mapping(address => mapping(address => address)) public getPool;
    address[] public allPools;

    error ZERO_ADDRESS();
    error POOL_ALREADY_EXISTS();
    error IDENTICAL_ADDRESSES();

    constructor(uint8 _fee) {
        fee = _fee;
    }

    function createLiquidityPool(
        address tokenA,
        address tokenB
    ) external returns (address pool) {
        // check for identical addresses, already existing pools & zero address
        if (tokenA == tokenB) revert IDENTICAL_ADDRESSES();
        if (tokenA == address(0) || tokenB == address(0)) revert ZERO_ADDRESS();
        if (getPool[tokenA][tokenB] != address(0)) revert POOL_ALREADY_EXISTS();
        // create new pool if passed conditions
        bytes memory bytecode = type(FakeUniswapPool).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));
        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        FakeUniswapPool(pool).initialize(tokenA, tokenB, fee);
        // populate mapping in both directions
        getPool[tokenA][tokenB] = pool;
        getPool[tokenB][tokenA] = pool;
        allPools.push(address(pool));
        emit PoolCreated(tokenA, tokenB, pool, allPools.length);
    }

    function allPoolsLength() external pure returns (uint256) {
        return allPools.length;
    }
}
