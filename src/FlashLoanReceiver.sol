// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC3156FlashBorrower} from "openzeppelin/interfaces/IERC3156FlashBorrower.sol";

import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {FakeUniswapPool} from "./FakeUniswapPool.sol";

/**
 * @title FlashLoanReceiver
 * @author Patrick Zimmerer
 * @notice A simple FlashLoanReceiver contract that is just used for testing purposes
 */
contract FlashLoanReceiver is IERC3156FlashBorrower {
    FakeUniswapPool pool;
    IERC20 token;
    address receiver;

    constructor(address _pool, address _token, address _receiver) {
        pool = FakeUniswapPool(_pool);
        token = IERC20(_token);
        receiver = _receiver;
    }

    function borrow() external {
        pool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(token),
            pool.maxFlashLoan(address(token)),
            bytes("")
        );
    }

    function onFlashLoan(
        address,
        address _token,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external returns (bytes32) {
        uint256 amountToBeRepaid = amount + fee;
        SafeERC20.safeTransfer(IERC20(_token), address(pool), amountToBeRepaid);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
