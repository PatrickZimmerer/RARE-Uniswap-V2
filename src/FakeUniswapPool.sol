// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IFakeUniswapERC20} from "./interfaces/IFakeUniswapERC20.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC3156FlashLender} from "openzeppelin/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "openzeppelin/interfaces/IERC3156FlashBorrower.sol";

import {Math} from "openzeppelin/utils/math/Math.sol";
import {SafeMath} from "openzeppelin/utils/math/SafeMath.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

import {Initializable} from "openzeppelin/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {UD60x18, intoUint128, intoUint256, ud, unwrap} from "prb-math/UD60x18.sol";

/**
 * @title FakeUniswapPool
 * @author Patrick Zimmerer
 * @notice A simple fake of the UniSwapV2Pair which will act as a Liquidity Pool once created by the factory
 */

contract FakeUniswapPool is
    IFakeUniswapERC20,
    IERC3156FlashLender,
    ERC20,
    Initializable,
    ReentrancyGuard
{
    using Math for uint256;
    using SafeMath for uint256;

    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    error RepayFailed();
    error UnsupportedCurrency();
    error CallbackFailed();

    event Swap(
        address indexed sender,
        uint256 amountAIn,
        uint256 amountBIn,
        uint256 amountAOut,
        uint256 amountBOut,
        address indexed to
    );
    event Sync(uint128 reserveA, uint128 reserveB);

    uint8 private _underlyingDecimals;

    address public factory;
    IERC20 private _tokenA;
    IERC20 private _tokenB;

    uint128 private reserveA; // uses single storage slot, accessible via getReserves
    uint128 private reserveB; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    uint8 private flashLoanFee;

    constructor() ERC20("Uniswap V2", "UNI-V2") {
        factory = msg.sender;
    }

    function initialize(
        address tokenA_,
        address tokenB_,
        uint8 flashLoanFee_
    ) external initializer {
        _tokenA = IERC20(tokenA_);
        (bool successA, uint8 assetADecimals) = _tryGetAssetDecimals(_tokenA);
        uint8 underlyingDecimalsA = successA ? assetADecimals : 18;

        _tokenB = IERC20(tokenB_);
        (bool successB, uint8 assetBDecimals) = _tryGetAssetDecimals(_tokenB);
        uint8 underlyingDecimalsB = successB ? assetBDecimals : 18;

        require(
            underlyingDecimalsA == underlyingDecimalsB,
            "decimals must equal"
        );
        _underlyingDecimals = underlyingDecimalsA;

        flashLoanFee = flashLoanFee_;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 balanceA,
        uint256 balanceB,
        uint128 _reserveA,
        uint128 _reserveB
    ) private {
        // require(balanceA <= uint112(-1) && balanceB <= uint112(-1), 'UniswapV2: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (timeElapsed > 0 && _reserveA != 0 && _reserveB != 0) {
            price0CumulativeLast += intoUint256(
                UD60x18.wrap(_reserveB).div(ud(_reserveA)).mul(ud(timeElapsed))
            );
            price1CumulativeLast += intoUint256(
                UD60x18.wrap(_reserveA).div(ud(_reserveB)).mul(ud(timeElapsed))
            );
        }
        reserveA = uint128(balanceA);
        reserveB = uint128(balanceB);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserveA, reserveB);
    }

    /**
     * @dev Attempts to fetch the asset decimals. A return value of false indicates that the attempt failed in some way.
     */
    function _tryGetAssetDecimals(
        IERC20 asset_
    ) private view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) = address(asset_)
            .staticcall(
                abi.encodeWithSelector(IERC20Metadata.decimals.selector)
            );
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    function decimals()
        public
        view
        virtual
        override(IERC20Metadata, ERC20)
        returns (uint8)
    {
        return _underlyingDecimals + _decimalsOffset();
    }

    function assetA() public view virtual override returns (address) {
        return address(_tokenA);
    }

    function assetB() public view virtual override returns (address) {
        return address(_tokenB);
    }

    function totalAssets()
        public
        view
        virtual
        returns (uint128 totalManagedAssetsA, uint128 totalManagedAssetsB)
    {
        return (reserveA, reserveB);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 4;
    }

    function convertToShares(
        uint256 assetsA,
        uint256 assetsB
    ) public view virtual override returns (uint256) {
        return _convertToShares(assetsA, assetsB, Math.Rounding.Down);
    }

    function convertToAssets(
        uint256 shares
    ) public view virtual override returns (uint256 assetsA, uint256 assetsB) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function maxDeposit(
        address
    ) public view virtual override returns (uint256, uint256) {
        return (type(uint256).max, type(uint256).max);
    }

    function maxRedeem(
        address owner
    ) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(
        uint256 assetsA,
        uint256 assetsB
    ) public view virtual override returns (uint256) {
        return _convertToShares(assetsA, assetsB, Math.Rounding.Down);
    }

    function previewRedeem(
        uint256 shares
    ) public view virtual override returns (uint256, uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function deposit(
        uint256 assetsA,
        uint256 assetsB,
        address receiver
    ) external override nonReentrant returns (uint256 shares) {
        (uint256 maxAssetsA, uint256 maxAssetsB) = maxDeposit(receiver);
        require(
            (assetsA <= maxAssetsA) && (assetsB <= maxAssetsB),
            "ERC4626: deposit more than max"
        );

        // Need to transfer before minting to avoid reenter.
        SafeERC20.safeTransferFrom(_tokenA, msg.sender, address(this), assetsA);
        SafeERC20.safeTransferFrom(_tokenB, msg.sender, address(this), assetsB);

        (uint128 _reserveA, uint128 _reserveB) = totalAssets();

        uint256 balanceA = _tokenA.balanceOf(address(this));
        uint256 balanceB = _tokenB.balanceOf(address(this));

        uint256 amountA = balanceA.sub(_reserveA);
        uint256 amountB = balanceB.sub(_reserveB);

        shares = previewDeposit(amountA, amountB);

        _mint(receiver, shares);
        _update(balanceA, balanceB, _reserveA, _reserveB);

        emit Deposit(msg.sender, receiver, assetsA, assetsB, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        external
        override
        nonReentrant
        returns (uint256 assetsA, uint256 assetsB)
    {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        (assetsA, assetsB) = previewRedeem(shares);
        require(
            assetsA > 0 && assetsB > 0,
            "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED"
        );

        _burn(owner, shares);

        (uint128 _reserveA, uint128 _reserveB) = totalAssets();

        // Need to transfer before returning asser to avoid reenter.
        SafeERC20.safeTransfer(_tokenA, receiver, assetsA);
        SafeERC20.safeTransfer(_tokenB, receiver, assetsB);

        uint256 balanceA = _tokenA.balanceOf(address(this));
        uint256 balanceB = _tokenB.balanceOf(address(this));
        _update(balanceA, balanceB, _reserveA, _reserveB);

        emit Withdraw(msg.sender, receiver, owner, assetsA, assetsB, shares);
    }

    function swap(
        uint256 amountAOut,
        uint256 amountBOut,
        address receiver
    ) external nonReentrant {
        require(
            amountAOut > 0 || amountBOut > 0,
            "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        (uint128 _reserveA, uint128 _reserveB) = totalAssets();
        require(
            amountAOut < _reserveA && amountBOut < _reserveB,
            "UniswapV2: INSUFFICIENT_LIQUIDITY"
        );

        if (amountAOut > 0)
            SafeERC20.safeTransfer(_tokenA, receiver, amountAOut);
        if (amountBOut > 0)
            SafeERC20.safeTransfer(_tokenB, receiver, amountBOut);

        uint256 balanceA = _tokenA.balanceOf(address(this));
        uint256 balanceB = _tokenB.balanceOf(address(this));

        uint256 amountAIn = balanceA > _reserveA - amountAOut
            ? balanceA - (_reserveA - amountAOut)
            : 0;
        uint256 amountBIn = balanceB > _reserveB - amountBOut
            ? balanceB - (_reserveB - amountBOut)
            : 0;

        require(
            amountAIn > 0 || amountBIn > 0,
            "UniswapV2: INSUFFICIENT_INPUT_AMOUNT"
        );

        uint256 balanceAAdjusted = balanceA.mul(1000).sub(amountAIn.mul(3));
        uint256 balanceBAdjusted = balanceB.mul(1000).sub(amountBIn.mul(3));

        require(
            balanceAAdjusted.mul(balanceBAdjusted) >=
                uint256(_reserveA).mul(_reserveB).mul(1000 ** 2),
            "UniswapV2: K"
        );

        _update(balanceA, balanceB, _reserveA, _reserveB);

        emit Swap(
            msg.sender,
            amountAIn,
            amountBIn,
            amountAOut,
            amountBOut,
            receiver
        );
    }

    function _convertToShares(
        uint256 assetsA,
        uint256 assetsB,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        if (totalSupply() == 0) {
            return Math.sqrt(assetsA * assetsB);
        } else {
            (uint128 _reserveA, uint128 _reserveB) = totalAssets();

            uint256 liquidityA = assetsA.mulDiv(
                totalSupply() + 10 ** _decimalsOffset(),
                _reserveA + 1,
                rounding
            );
            uint256 liquidityB = assetsB.mulDiv(
                totalSupply() + 10 ** _decimalsOffset(),
                _reserveB + 1,
                rounding
            );
            return Math.min(liquidityA, liquidityB);
        }
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256, uint256) {
        // (uint256 balanceA, uint256 balanceB )= totalAssets();
        uint256 balanceA = _tokenA.balanceOf(address(this));
        uint256 balanceB = _tokenB.balanceOf(address(this));

        return (
            shares.mulDiv(
                balanceA + 1,
                totalSupply() + 10 ** _decimalsOffset(),
                rounding
            ),
            shares.mulDiv(
                balanceB + 1,
                totalSupply() + 10 ** _decimalsOffset(),
                rounding
            )
        );
    }

    function maxFlashLoan(address token) external view returns (uint256) {
        if (token == address(_tokenA)) {
            return _tokenA.balanceOf(address(this));
        }
        if (token == address(_tokenB)) {
            return _tokenB.balanceOf(address(this));
        }
        return 0;
    }

    function flashFee(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        if (token != address(_tokenA) && token != address(_tokenB)) {
            revert UnsupportedCurrency();
        }

        return amount.mul(uint256(flashLoanFee)).div(100);
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        if (token != address(_tokenA) && token != address(_tokenB)) {
            revert UnsupportedCurrency();
        }

        IERC20 _token = IERC20(token);
        uint256 balanceBefore = _token.balanceOf(address(this));
        SafeERC20.safeTransfer(_token, address(receiver), amount);
        uint256 fee = flashFee(token, amount);

        if (
            receiver.onFlashLoan(
                msg.sender,
                address(_token),
                amount,
                fee,
                data
            ) != CALLBACK_SUCCESS
        ) {
            revert CallbackFailed();
        }
        if (_token.balanceOf(address(this)) < balanceBefore + fee) {
            revert RepayFailed();
        }

        (uint128 _reserveA, uint128 _reserveB) = totalAssets();
        uint256 balanceA = _tokenA.balanceOf(address(this));
        uint256 balanceB = _tokenB.balanceOf(address(this));
        _update(balanceA, balanceB, _reserveA, _reserveB);

        return true;
    }
}
