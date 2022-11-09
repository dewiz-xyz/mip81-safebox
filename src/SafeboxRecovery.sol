// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.16;

import {VatAbstract} from "dss-interfaces/dss/VatAbstract.sol";
import {GemAbstract} from "dss-interfaces/ERC/GemAbstract.sol";
import {SafeboxLike} from "./SafeboxLike.sol";

/**
 * @author amusingaxl
 * @title A facitilty to allow Dai holders to recover funds from a Safebox contract after Emergency Shutdown.
 * @dev
 * - Checks if there is outstanding token balance in the `safebox` contract and transfers it to the `recipient`.
 * - Assumes that the provided `recipient` will have `approve`d this contract to spend tokens enough on their behalf.
 */
contract SafeboxRecovery {
    enum State {
        DISABLED,
        ENABLED
    }

    /// @notice The max supported gem price, in Dai with 10**18 precision.
    /// @dev Set to 10**15 (1 quatrillion) Dai. Values larger than this will cause math overflow issues.
    ///                                     1 quatrillion ────┐    ┌──── 18 decimals
    ///                                                       ▼    ▼
    uint256 public constant MAX_SUPPORTED_PRICE = 10 ** uint256(15 + 18);
    /// @notice The min supported decimal places for gems and tokens.
    uint8 public constant MIN_SUPPORTED_DECIMALS = 2;
    /// @notice The max supported decimal places for gems and tokens.
    uint8 public constant MAX_SUPPORTED_DECIMALS = 27;

    /// @notice The safebox reference.
    SafeboxLike public immutable safebox;

    /// @notice The MCD Vat module reference.
    VatAbstract public immutable vat;

    /// @notice The ERC-20 token to be released by this contract.
    GemAbstract public immutable token;

    /// @notice The collateral token to be redeemed by tokens with this contract.
    GemAbstract public immutable gem;

    /// @dev The decimal conversion factor from gem to token units.
    uint256 internal immutable conversionFactor;

    /// @notice The contract state.
    State public state;

    /// @notice The price for each unit of `gem`, with 10**18 precision.
    /// @dev Fits in the same storage slot as `state`.
    uint248 public price;

    /**
     * @notice The recovery has been enabled.
     */
    event Enable();
    /**
     * @notice A redemption was made.
     * @param sender The `msg.sender`.
     * @param coinAmt The amount of gems redeemed.
     * @param coinAmt The amount of coins sent back to the sender.
     */
    event Redeem(address indexed sender, uint256 gemAmt, uint256 coinAmt);

    /**
     * @param _vat The MCD vat module.
     * @param _token The token to use in the recovery.
     * @param _safebox The safebox contract to recover tokens from.
     * @param _gem The collateral token related to the safebox.
     */
    constructor(address _vat, address _token, address _safebox, address _gem) {
        // Both `vat` and `token` are immutable on Safebox, so we can safely extract it here to save some gas later.
        GemAbstract __token = SafeboxLike(_safebox).token();
        VatAbstract __vat = SafeboxLike(_safebox).vat();

        require(_vat == address(__vat), "SafeboxRecovery/vat-mismatch");
        require(_token == address(__token), "SafeboxRecovery/token-mismatch");

        uint8 tokenDecimals = __token.decimals();
        require(
            tokenDecimals >= MIN_SUPPORTED_DECIMALS && tokenDecimals <= MAX_SUPPORTED_DECIMALS,
            "SafeboxRecovery/token-decimals-out-of-bounds"
        );

        GemAbstract __gem = GemAbstract(_gem);
        uint8 gemDecimals = __gem.decimals();
        require(
            gemDecimals >= MIN_SUPPORTED_DECIMALS && gemDecimals <= MAX_SUPPORTED_DECIMALS,
            "SafeboxRecovery/gem-decimals-out-of-bounds"
        );

        conversionFactor = 10 ** (gemDecimals - tokenDecimals);

        safebox = SafeboxLike(_safebox);
        vat = __vat;
        token = __token;
        gem = __gem;
    }

    /**
     * @notice Enables the recovery of Safebox funds.
     * @dev Can only be called after Emergency Shutdown.
     */
    function enable() external {
        require(state == State.DISABLED, "SafeboxRecovery/already-enabled");
        require(vat.live() == 0, "SafeboxRecovery/vat-still-live");

        // Withdraws any remaining tokens from the Safebox in case nobody has done it yet.
        // Since vat.live() == 0, this function will now be permissionless.
        safebox.withdraw(token.balanceOf(address(safebox)));

        // After withdrawing, tokens will be sent to the recipient.
        // We need to pull the entire recipient token balance into this contract.
        address recipient = safebox.recipient();
        uint256 balance = token.balanceOf(recipient);
        token.transferFrom(recipient, address(this), balance);

        state = State.ENABLED;
        price = uint248(((balance * conversionFactor) * WAD) / gem.totalSupply());

        require(price > 0 && price <= MAX_SUPPORTED_PRICE, "SafeboxRecovery/price-out-of-bounds");

        emit Enable();
    }

    /**
     * @notice Redeem gems for tokens, which are sent back to the sender.
     * @dev Precision conversion rounding issues may prevent redeeming very small amounts of gem.
     * Check `minRedeemable()` to know the smallest amount that can be redeemed.
     * @param gemAmt The amount of gems to redeem.
     */
    function redeem(uint256 gemAmt) external {
        require(state == State.ENABLED, "SafeboxRecovery/not-enabled");

        uint256 tokenAmt = gemToToken(gemAmt);
        // Prevents a very small amount of gems to be redeemed, as this would essentially
        // burn the gem tokens without giving the caller anything back.
        require(tokenAmt > 0, "SafeboxRecovery/too-few-gems");

        gem.transferFrom(msg.sender, address(this), gemAmt);
        token.transfer(msg.sender, tokenAmt);

        emit Redeem(msg.sender, gemAmt, tokenAmt);
    }

    /*//////////////////////////////////////
             Helper view functions
    //////////////////////////////////////*/

    /**
     * @notice Returns the amount of tokens currently deposited in this contract.
     * @return tokenAmt The token balance of this contract.
     */
    function currentlyDeposited() public view returns (uint256 tokenAmt) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Returns the minimum amount of gems that can be redeemed by this contract.
     * @dev Because of rounding errors, sending a smaller amount of gems will lead to a token transfer o value `0`.
     * @return gemAmt The min amount of gems required for redemption.
     */
    function minRedeemable() public view returns (uint256 gemAmt) {
        return tokenToGem(1);
    }

    /**
     * @notice Returns the amount of gems that can currently be redeemed by this contract.
     * @return gemAmt The amount of gems currently available for redemption.
     */
    function currentlyRedeemable() public view returns (uint256 gemAmt) {
        return tokenToGem(currentlyDeposited());
    }

    /**
     * @notice Returns the amount of gems already reedeemed by this contract.
     * @return gemAmt The amount of gems redeemed.
     */
    function totalRedeemed() public view returns (uint256 gemAmt) {
        return gem.balanceOf(address(this));
    }

    /*//////////////////////////////////////
                Unit Conversion
    //////////////////////////////////////*/

    /**
     * @notice Converts gems into tokens with the required precision conversion.
     * @param gemAmt The amount of gems.
     * @return tokenAmt The amount tokens.
     */
    function gemToToken(uint256 gemAmt) public view returns (uint256 tokenAmt) {
        return mul(gemAmt, price) / conversionFactor / WAD;
    }

    /**
     * @notice Converts tokens into gems with the required precision conversion.
     * @param tokenAmt The amount tokens.
     * @return gemAmt The amount of gems.
     */
    function tokenToGem(uint256 tokenAmt) public view returns (uint256 gemAmt) {
        return divup(mul(mul(tokenAmt, WAD), conversionFactor), price);
    }

    /*//////////////////////////////////////
                      Math
    //////////////////////////////////////*/

    /// @dev The default 18 decimals precision.
    uint256 internal constant WAD = 10 ** 18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "Math/add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Math/sub-overflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "Math/mul-overflow");
    }

    /**
     * @dev Divides x/y, but rounds it up.
     */
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }
}
