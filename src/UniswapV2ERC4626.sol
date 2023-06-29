// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "openzeppelin/token/ERC20/extensions/ERC4626.sol";

contract UniswapV2LPToken is ERC4626 {
    constructor(
        address _underlyingAsset
    ) ERC20("UniswapLP", "LP") ERC4626(IERC20(_underlyingAsset)) {}

    /**
     * @dev Shares are minted when depositing
     */
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    /**
     * @dev Shares are burned when pulling out the liquidity
     */ function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
