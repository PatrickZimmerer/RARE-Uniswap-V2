// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {FakeUniswapPoolFactory} from "../src/FakeUniswapPoolFactory.sol";
import {FakeUniswapPool} from "../src/FakeUniswapPool.sol";

contract FakeUniswapPoolFactoryTest is Test {
    address deployer = makeAddr("Deployer");

    FakeUniswapPoolFactory factory;

    error ZERO_ADDRESS();
    error POOL_ALREADY_EXISTS();
    error IDENTICAL_ADDRESSES();

    IERC20 tokenA;
    IERC20 tokenB;

    function setUp() public {
        vm.startPrank(deployer);
        vm.deal(deployer, 1 ether);
        vm.label(deployer, "Deployer");

        factory = new FakeUniswapPoolFactory(5); // fee 5%

        tokenA = IERC20(address(new MockERC20("TokenA", "TA", 18)));
        tokenB = IERC20(address(new MockERC20("TokenB", "TB", 18)));

        vm.label(address(tokenA), "TokenA");
        vm.label(address(tokenB), "TokenB");

        vm.stopPrank();
    }

    function test_createPool() external {
        vm.startPrank(deployer);

        address poolAddress = factory.createLiquidityPool(
            address(tokenA),
            address(tokenB)
        );

        FakeUniswapPool pool = FakeUniswapPool(poolAddress);

        assertEq(pool.assetA(), address(tokenA));
        assertEq(pool.assetB(), address(tokenB));

        vm.stopPrank();
    }

    function test_Revert_IDENTICAL_ADDRESSES() external {
        vm.startPrank(deployer);

        vm.expectRevert(IDENTICAL_ADDRESSES.selector);
        factory.createLiquidityPool(address(tokenA), address(tokenA));

        vm.stopPrank();
    }

    function test_Revert_ZERO_ADDRESS() external {
        vm.startPrank(deployer);

        vm.expectRevert(ZERO_ADDRESS.selector);
        factory.createLiquidityPool(address(tokenA), address(0));

        vm.expectRevert(ZERO_ADDRESS.selector);
        factory.createLiquidityPool(address(0), address(tokenB));

        vm.stopPrank();
    }

    function test_Revert_POOL_ALREADY_EXISTS() external {
        vm.startPrank(deployer);

        factory.createLiquidityPool(address(tokenA), address(tokenB));

        vm.expectRevert(POOL_ALREADY_EXISTS.selector);
        factory.createLiquidityPool(address(tokenB), address(tokenA));

        vm.stopPrank();
    }
}
