// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
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

    uint112 private reserveA; // uses single storage slot, accessible via getReserves
    uint112 private reserveB; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

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

    function getReserves()
        public
        view
        returns (
            uint112 _reserveA,
            uint112 _reserveB,
            uint32 _blockTimestampLast
        )
    {
        _reserveA = reserveA;
        _reserveB = reserveB;
        _blockTimestampLast = blockTimestampLast;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint balanceA,
        uint balanceB,
        uint112 _reserveA,
        uint112 _reserveB
    ) private {
        require(
            balanceA <= type(uint112).max && balanceB <= type(uint112).max,
            "UniswapV2: OVERFLOW"
        );
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserveA != 0 && _reserveB != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast +=
                uint(UQ112x112.encode(_reserveB).uqdiv(_reserveA)) *
                timeElapsed;
            price1CumulativeLast +=
                uint(UQ112x112.encode(_reserveA).uqdiv(_reserveB)) *
                timeElapsed;
        }
        reserveA = uint112(balanceA);
        reserveB = uint112(balanceB);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserveA, reserveB);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(
        uint112 _reserveA,
        uint112 _reserveB
    ) private returns (bool feeOn) {
        address feeTo = FakeUniswapToken(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserveA) * _reserveB);
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply * rootK - rootKLast;
                    uint denominator = rootK * 5 + rootKLast;
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserveA, uint112 _reserveB, ) = getReserves(); // gas savings
        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));
        uint amountA = balanceA - _reserveA;
        uint amountB = balanceB - _reserveB;

        bool feeOn = _mintFee(_reserveA, _reserveB);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(
                (amountA * _totalSupply) / _reserveA,
                (amountB * _totalSupply) / _reserveB
            );
        }
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balanceA, balanceB, _reserveA, _reserveB);
        if (feeOn) kLast = uint(reserveA) * reserveB; // reserveA and reserve1 are up-to-date
        emit Mint(msg.sender, amountA, amountB);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(
        address to
    ) external lock returns (uint amountA, uint amountB) {
        (uint112 _reserveA, uint112 _reserveB, ) = getReserves(); // gas savings
        address _tokenA = tokenA; // gas savings
        address _tokenB = tokenB; // gas savings
        uint balanceA = IERC20(_tokenA).balanceOf(address(this));
        uint balanceB = IERC20(_tokenB).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserveA, _reserveB);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amountA = (liquidity * balanceA) / _totalSupply; // using balances ensures pro-rata distribution
        amountB = (liquidity * balanceB) / _totalSupply; // using balances ensures pro-rata distribution
        require(
            amountA > 0 && amountB > 0,
            "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED"
        );
        _burn(address(this), liquidity);
        _safeTransfer(_tokenA, to, amountA);
        _safeTransfer(_tokenB, to, amountB);
        balanceA = IERC20(_tokenA).balanceOf(address(this));
        balanceB = IERC20(_tokenB).balanceOf(address(this));

        _update(balanceA, balanceB, _reserveA, _reserveB);
        if (feeOn) kLast = uint(reserveA).mul(reserveB); // reserveA and reserveB are up-to-date
        emit Burn(msg.sender, amountA, amountB, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external lock {
        require(
            amount0Out > 0 || amount1Out > 0,
            "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        (uint112 _reserveA, uint112 _reserveB, ) = getReserves(); // gas savings
        require(
            amount0Out < _reserveA && amount1Out < _reserveB,
            "UniswapV2: INSUFFICIENT_LIQUIDITY"
        );

        uint balance0;
        uint balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _tokenA = tokenA;
            address _tokenB = tokenB;
            require(to != _tokenA && to != _tokenB, "UniswapV2: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_tokenA, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_tokenB, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0)
                FakeUniswapToken(to).uniswapV2Call(
                    msg.sender,
                    amount0Out,
                    amount1Out,
                    data
                );
            balance0 = IERC20(_tokenA).balanceOf(address(this));
            balance1 = IERC20(_tokenB).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserveA - amount0Out
            ? balance0 - (_reserveA - amount0Out)
            : 0;
        uint amount1In = balance1 > _reserveB - amount1Out
            ? balance1 - (_reserveB - amount1Out)
            : 0;
        require(
            amount0In > 0 || amount1In > 0,
            "UniswapV2: INSUFFICIENT_INPUT_AMOUNT"
        );
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint balance0Adjusted = balance0 * 1000 - amount0In * 3;
            uint balance1Adjusted = balance1 * 1000 - amount1In * 3;
            require(
                balance0Adjusted * balance1Adjusted >=
                    uint(_reserveA) * _reserveB * (1000 ** 2),
                "UniswapV2: K"
            );
        }

        _update(balance0, balance1, _reserveA, _reserveB);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _tokenA = tokenA; // gas savings
        address _tokenB = tokenB; // gas savings
        _safeTransfer(
            _tokenA,
            to,
            IERC20(_tokenA).balanceOf(address(this)) - reserveA
        );
        _safeTransfer(
            _tokenB,
            to,
            IERC20(_tokenB).balanceOf(address(this)) - reserveB
        );
    }

    // force reserves to match balances
    function sync() external lock {
        _update(
            IERC20(tokenA).balanceOf(address(this)),
            IERC20(tokenB).balanceOf(address(this)),
            reserveA,
            reserveB
        );
    }

    function _safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");
        require(
            returndata.length == 0 || abi.decode(returndata, (bool)),
            "SafeERC20: ERC20 operation did not succeed"
        );
    }
}
