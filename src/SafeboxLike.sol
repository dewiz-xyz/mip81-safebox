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

interface SafeboxLike {
    /**
     * @notice `usr` was granted owner access.
     * @param usr The user address.
     */
    event Rely(address indexed usr);
    /**
     * @notice `usr` owner access was revoked.
     * @param usr The user address.
     */
    event Deny(address indexed usr);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. The supported values are: "recipient".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice The owner withdrawn tokens from the safebox.
     * @param recipient The token recipient.
     * @param amount The amount withdrawn.
     */
    event Withdraw(address indexed recipient, uint256 amount);
    /**
     * @notice `usr` was granted custodian access.
     * @param usr The user address.
     */
    event AddCustodian(address indexed usr);
    /**
     * @notice `usr` custodian access was revoked.
     * @param usr The user address.
     */
    event RemoveCustodian(address indexed usr);
    /**
     * @notice The recipient has been set.
     * @param recipient The new recipient address.
     */
    event SetRecipient(address indexed recipient);

    /// @notice MCD Vat module.
    function vat() external view returns (VatAbstract);

    /// @notice The ERC-20 token to be held the this contract.
    function token() external view returns (GemAbstract);

    /// @notice Addresses with owner access in the contract. `wards[usr]`
    function wards(address) external view returns (uint256);

    /// @notice Addresses with custodian access in the contract. `custodians[usr]`
    function custodians(address) external view returns (uint256);

    /// @notice The recipient for the tokens held in the contract.
    function recipient() external view returns (address);

    /// @notice Reference to the new recipient when it is to be changed.
    function pendingRecipient() external view returns (address);

    /**
     * @notice Withdraws tokens from this contract.
     * @dev Anyone can call this function after MakerDAO governance executes an Emergency Shutdown.
     */
    function withdraw(uint256) external;

    /*//////////////////////////////////
            MakerDAO Interfaces
    //////////////////////////////////*/

    /**
     * @notice Grants `usr` owner access to this contract.
     */
    function rely(address) external;

    /**
     * @notice Revokes `usr` owner access from this contract.
     */
    function deny(address) external;

    /**
     * @notice Updates a contract parameter.
     */
    function file(bytes32, address) external;

    /*//////////////////////////////////
            Custodian Interfaces
    //////////////////////////////////*/

    /**
     * @notice Check if an address has `owner` access on this contract.
     * @return Whether `usr` is a ward or not.
     */
    function isOwner(address) external view returns (bool);

    /**
     * @notice Check if an address has `custodian` access on this contract.
     * @return Whether `usr` is a ward or not.
     */
    function isCustodian(address) external view returns (bool);

    /**
     * @notice Adds a new custodian to this contract.
     */
    function addCustodian(address) external;

    /**
     * @notice Removes a custodian from this contract.
     */
    function removeCustodian(address) external;

    /**
     * @notice Approves the change in the recipient.
     * @dev Reverts if `pendingRecipient` has not been set or if `_recipient` does not match it.
     */
    function approveChangeRecipient(address) external;
}
