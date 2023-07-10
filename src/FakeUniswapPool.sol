// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "forge-std/console.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin/interfaces/IERC3156FlashLender.sol";
import {UD60x18, ud} from "prb-math/UD60x18.sol";
import "openzeppelin/security/ReentrancyGuard.sol";
import "./FakeUniswapToken.sol";

contract FakeUniswapPool is
    FakeUniswapToken,
    IERC3156FlashLender,
    ReentrancyGuard
{
    uint public constant MINIMUM_LIQUIDITY = 10 ** 3;

    address public factory;
    address public tokenA;
    address public tokenB;

    UD60x18 private reserveA;
    UD60x18 private reserveB;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserveA * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;

    event Mint(address indexed sender, uint amountA, uint amountB);
    event Burn(
        address indexed sender,
        uint amountA,
        uint amountB,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint amountAIn,
        uint amountBIn,
        uint amountAOut,
        uint amountBOut,
        address indexed to
    );
    event Sync(uint112 reserveA, uint112 reserve1);

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
    ) {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _tokenA, address _tokenB) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN"); // sufficient check
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    /// @notice this is copied from Solmate because "ERC20" was in both OZ and Solmate libraries
    /// is there a way to have namespaces in solidity?
    function safeTransferFrom(
        ERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        bool success;

        /// @solidity memory-safe-assembly
        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(
                freeMemoryPointer,
                0x23b872dd00000000000000000000000000000000000000000000000000000000
            )
            mstore(
                add(freeMemoryPointer, 4),
                and(from, 0xffffffffffffffffffffffffffffffffffffffff)
            ) // Append and mask the "from" argument.
            mstore(
                add(freeMemoryPointer, 36),
                and(to, 0xffffffffffffffffffffffffffffffffffffffff)
            ) // Append and mask the "to" argument.
            mstore(add(freeMemoryPointer, 68), amount) // Append the "amount" argument. Masking not required as it's a full 32 byte type.

            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(
                    and(eq(mload(0), 1), gt(returndatasize(), 31)),
                    iszero(returndatasize())
                ),
                // We use 100 because the length of our calldata totals up like so: 4 + 32 * 3.
                // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                // Counterintuitively, this call must be positioned second to the or() call in the
                // surrounding and() call or else returndatasize() will be zero during the computation.
                call(gas(), token, 0, freeMemoryPointer, 100, 0, 32)
            )
        }

        require(success, "TRANSFER_FROM_FAILED");
    }
}
