// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "forge-std/console.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin/interfaces/IERC3156FlashLender.sol";
import "openzeppelin/security/ReentrancyGuard.sol";

contract FakeUniswapPool is ERC20, IERC3156FlashLender, ReentrancyGuard {
    address public factory;
    address public tokenA;
    address public tokenB;

    uint112 private reserveA; // uses single storage slot, accessible via getReserves
    uint112 private reserveB; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(
        address _tokenA,
        address _tokenB,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol
    ) {}

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserveA;
        _reserve1 = reserveB;
        _blockTimestampLast = blockTimestampLast;
    }
}
