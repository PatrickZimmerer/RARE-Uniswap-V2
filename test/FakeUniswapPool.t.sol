// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {FlashLoanReceiver} from "../src/FlashLoanReceiver.sol";
import {FakeUniswapPool} from "../src/FakeUniswapPool.sol";

contract FakeUniswapPoolTest is Test {
    address deployer = makeAddr("Deployer");
    address alice = makeAddr("Alice");

    FakeUniswapPool pool;

    IERC20 tokenA;
    IERC20 tokenB;

    function setUp() public {
        vm.startPrank(deployer);
        vm.deal(deployer, 1 ether);
        vm.label(deployer, "Deployer");
        vm.label(alice, "Alice");

        pool = new FakeUniswapPool();

        tokenA = IERC20(address(new MockERC20("TokenA", "TA", 18)));
        tokenB = IERC20(address(new MockERC20("TokenB", "TB", 18)));

        vm.label(address(tokenA), "TokenA");
        vm.label(address(tokenB), "TokenB");

        vm.stopPrank();
    }

    // modifiers will act as a before each for certain tests
    modifier deployerInit() {
        vm.startPrank(deployer);

        deal({token: address(tokenA), to: deployer, give: 200 ether});
        deal({token: address(tokenB), to: deployer, give: 300 ether});

        assertEq(
            tokenA.balanceOf(deployer),
            200 ether,
            "Unexpected Faucet for tokenA"
        );
        assertEq(
            tokenB.balanceOf(deployer),
            300 ether,
            "Unexpected Faucet for tokenA"
        );

        pool.initialize(address(tokenA), address(tokenB), 1);

        vm.stopPrank();
        _;
    }

    modifier deployerAddsFirstLiquiditySuccess() {
        vm.startPrank(deployer);

        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);

        pool.deposit(10 ether, 10 ether, deployer); // + 10 LP

        (uint128 reserveA, uint128 reserveB) = pool.totalAssets();
        assertEq(reserveA, 10 ether, "unexpected reserveA");
        assertEq(reserveB, 10 ether, "unexpected reserveB");

        assertEq(
            pool.balanceOf(deployer),
            10 ether,
            "initial share should be sqrt( tokenA * tokenB )"
        );
        assertEq(pool.totalSupply(), 10 ether, "unexpected total supply");

        vm.stopPrank();
        _;
    }

    function test_deposit()
        external
        deployerInit
        deployerAddsFirstLiquiditySuccess
    {
        // the actual testing here is handled by the modifiers
        vm.startPrank(deployer);
        vm.stopPrank();
    }

    function test_double_deposits()
        external
        deployerInit
        deployerAddsFirstLiquiditySuccess
    {
        vm.startPrank(deployer);

        vm.warp(37);
        pool.deposit(20 ether, 20 ether, deployer); // + 20 LP

        (uint128 reserveA, uint128 reserveB) = pool.totalAssets();
        assertEq(reserveA, 30 ether, "unexpected reserveA");
        assertEq(reserveB, 30 ether, "unexpected reserveB");

        uint256 decimalsOffset = 5;
        assertApproxEqAbs(
            pool.balanceOf(deployer),
            30 ether,
            10 * (10 ** decimalsOffset),
            "should approximately equal original + added"
        );
        assertApproxEqAbs(
            pool.totalSupply(),
            30 ether,
            10 * (10 ** decimalsOffset),
            "unexpected total supply"
        );

        vm.stopPrank();
    }

    function test_unbalanced_deposits()
        external
        deployerInit
        deployerAddsFirstLiquiditySuccess
    {
        vm.startPrank(deployer);

        vm.warp(37);
        pool.deposit(20 ether, 40 ether, deployer); // + 20 LP

        (uint128 reserveA, uint128 reserveB) = pool.totalAssets();
        assertEq(reserveA, 30 ether, "unexpected reserveA");
        assertEq(reserveB, 50 ether, "unexpected reserveB");

        uint256 decimalsOffset = 5;
        assertApproxEqAbs(
            pool.balanceOf(deployer),
            30 ether,
            10 * (10 ** decimalsOffset),
            "should approximately equal original + added"
        );

        vm.stopPrank();
    }

    function test_redeem()
        external
        deployerInit
        deployerAddsFirstLiquiditySuccess
    {
        vm.startPrank(deployer);

        vm.warp(37);

        uint256 tokenABalanceBeforeRedeem = tokenA.balanceOf(deployer);
        uint256 tokenBBalanceBeforeRedeem = tokenB.balanceOf(deployer);

        pool.approve(address(pool), type(uint256).max);
        uint256 shares = pool.balanceOf(deployer); // 10 ether
        pool.redeem(shares, deployer, deployer);

        uint256 tokenABalanceAfterRedeem = tokenA.balanceOf(deployer);
        uint256 tokenBBalanceAfterRedeem = tokenB.balanceOf(deployer);

        uint256 decimalsOffset = 5;

        (uint128 reserveA, uint128 reserveB) = pool.totalAssets();
        assertApproxEqAbs(
            reserveA,
            0 ether,
            10 * (10 ** decimalsOffset),
            "unexpected reserveA"
        );
        assertApproxEqAbs(
            reserveB,
            0 ether,
            10 * (10 ** decimalsOffset),
            "unexpected reserveB"
        );

        assertApproxEqAbs(
            pool.balanceOf(deployer),
            0 ether,
            10 * (10 ** decimalsOffset),
            "initial share should be sqrt( tokenA * tokenB )"
        );
        assertApproxEqAbs(
            pool.totalSupply(),
            0 ether,
            10 * (10 ** decimalsOffset),
            "unexpected total supply"
        );

        assertApproxEqAbs(
            tokenABalanceAfterRedeem,
            tokenABalanceBeforeRedeem + 10 ether,
            10 * (10 ** decimalsOffset),
            "unexpected tokenA balance of deployer"
        );
        assertApproxEqAbs(
            tokenBBalanceAfterRedeem,
            tokenBBalanceBeforeRedeem + 10 ether,
            10 * (10 ** decimalsOffset),
            "unexpected tokenB balance of deployer"
        );

        vm.stopPrank();
    }

    function test_appoveSomeoneThen_redeem()
        external
        deployerInit
        deployerAddsFirstLiquiditySuccess
    {
        vm.startPrank(deployer);

        pool.approve(alice, type(uint256).max);
        pool.approve(address(pool), type(uint256).max);

        vm.stopPrank();
        vm.startPrank(alice);

        vm.warp(37);

        uint256 tokenABalanceBeforeRedeem = tokenA.balanceOf(alice);
        uint256 tokenBBalanceBeforeRedeem = tokenB.balanceOf(alice);

        uint256 shares = pool.balanceOf(deployer); // 10 ether
        pool.redeem(shares, alice, deployer);

        uint256 tokenABalanceAfterRedeem = tokenA.balanceOf(alice);
        uint256 tokenBBalanceAfterRedeem = tokenB.balanceOf(alice);

        uint256 decimalsOffset = 5;

        (uint128 reserveA, uint128 reserveB) = pool.totalAssets();
        assertApproxEqAbs(
            reserveA,
            0 ether,
            10 * (10 ** decimalsOffset),
            "unexpected reserveA"
        );
        assertApproxEqAbs(
            reserveB,
            0 ether,
            10 * (10 ** decimalsOffset),
            "unexpected reserveB"
        );

        assertApproxEqAbs(
            pool.balanceOf(deployer),
            0 ether,
            10 * (10 ** decimalsOffset),
            "initial share should be sqrt( tokenA * tokenB )"
        );
        assertApproxEqAbs(
            pool.totalSupply(),
            0 ether,
            10 * (10 ** decimalsOffset),
            "unexpected total supply"
        );

        assertApproxEqAbs(
            tokenABalanceAfterRedeem,
            tokenABalanceBeforeRedeem + 10 ether,
            10 * (10 ** decimalsOffset),
            "unexpected tokenA balance of deployer"
        );
        assertApproxEqAbs(
            tokenBBalanceAfterRedeem,
            tokenBBalanceBeforeRedeem + 10 ether,
            10 * (10 ** decimalsOffset),
            "unexpected tokenB balance of deployer"
        );

        vm.stopPrank();
    }

    function test_swap()
        external
        deployerInit
        deployerAddsFirstLiquiditySuccess
    {
        vm.startPrank(alice);

        deal({token: address(tokenA), to: alice, give: 1 ether});

        uint256 amountOut = 0.9 ether;
        tokenA.transfer(address(pool), 1 ether);
        pool.swap(0, amountOut, alice);

        assertEq(tokenA.balanceOf(alice), 0 ether, "unexpected tokenA balance");
        assertEq(
            tokenB.balanceOf(alice),
            0.9 ether,
            "unexpected tokenB balance"
        );

        (uint128 reserveA, uint128 reserveB) = pool.totalAssets();
        assertEq(reserveA, 10 ether + 1 ether, "unexpected reserveA");
        assertEq(reserveB, 10 ether - 0.9 ether, "unexpected reserveB");

        vm.stopPrank();
    }

    function test_flashLoan()
        external
        deployerInit
        deployerAddsFirstLiquiditySuccess
    {
        vm.startPrank(alice);
        deal({token: address(tokenA), to: alice, give: 1 ether});

        FlashLoanReceiver receiver = new FlashLoanReceiver(
            address(pool),
            address(tokenA),
            alice
        );

        tokenA.transfer(address(receiver), 1 ether);
        uint256 fee = pool.flashFee(
            address(tokenA),
            pool.maxFlashLoan(address(tokenA))
        );
        receiver.borrow();

        (uint128 reserveA, ) = pool.totalAssets();
        assertEq(reserveA, 10 ether + fee, "unexpected reserveA");

        vm.stopPrank();
    }
}
