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

/**
 * @author amusingaxl
 * @title A safebox for ERC20 tokens.
 * @notice
 * - The `owner`(MakerDAO Governance) is in full control of how much and when it can send tokens to `recipient`.
 *     - MakerDAO Governance could add other owners if required in the future (i.e.: automation of the Safebox balance).
 * - If MakerDAO governance ever executes an Emergency Shutdown, anyone can send tokens to `recipient`.
 *     - This prevents tokens being stuck in this contract when the governance smart contract is no longer operational.
 * - The `custodian` cooperation is required whenever the `owner` wants to update the `recipient`.
 */
contract Safebox {
    /// @notice MCD Vat module.
    VatLike public immutable vat;
    /// @notice The ERC20 token to be hold in this contract.
    ERC20Like public immutable token;

    /// @notice Addresses with owner access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;
    /// @notice Addresses with custodian access on this contract. `custodians[usr]`
    mapping(address => uint256) public custodians;

    /// @notice The recipient for the tokens held in this contract.
    address public recipient;
    /// @notice Reference to the new recipient when it is to be changed.
    address public pendingRecipient;

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
     * @notice A deposit was made into the safebox.
     * @param sender The token sender.
     * @param amount The amount deposited.
     */
    event Deposit(address indexed sender, uint256 amount);
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
     * @notice The recipient has been sucessfully changed.
     * @param recipient The new recipient address.
     */
    event RecipientChange(address indexed recipient);

    modifier auth() {
        require(wards[msg.sender] == 1, "Safebox/not-ward");
        _;
    }

    modifier onlyCustodian() {
        require(custodians[msg.sender] == 1, "Safebox/not-custodian");
        _;
    }

    /**
     * @param _vat The MCD vat module.
     * @param _token The ERC20 token to be hold in this contract.
     * @param _owner The safebox owner.
     * @param _custodian The safebox custodian.
     * @param _recipient The recipient for tokens in the safebox.
     */
    constructor(address _vat, address _token, address _owner, address _custodian, address _recipient) {
        require(_recipient != address(0), "Safebox/invalid-recipient");

        wards[_owner] = 1;
        emit Rely(_owner);

        custodians[_custodian] = 1;
        emit AddCustodian(_custodian);

        vat = VatLike(_vat);
        token = ERC20Like(_token);
        recipient = _recipient;
    }

    /*//////////////////////////////////
                 Operations
    //////////////////////////////////*/

    /**
     * @notice Withdraws ERC20-like tokens from this contract.
     * @dev Anyone can call this function after MakerDAO governance executes an Emergency Shutdown.
     * @param amount The amount of tokens.
     */
    function withdraw(uint256 amount) external {
        require(wards[msg.sender] == 1 || vat.live() == 0, "Safebox/not-ward");

        token.transfer(recipient, amount);
        emit Withdraw(recipient, amount);
    }

    /**
     * @notice Deposits ERC20-like tokens into this contract.
     * @param amount The amount of tokens.
     */
    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /*//////////////////////////////////
            MakerDAO Interfaces
    //////////////////////////////////*/

    /**
     * @notice Grants `usr` owner access to this contract.
     * @param usr The user address.
     */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
     * @notice Revokes `usr` owner access from this contract.
     * @param usr The user address.
     */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. `"recipient"`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "Safebox/vat-not-live");

        if (what == "recipient") {
            require(data != address(0), "Safebox/invalid-recipient");
            pendingRecipient = data;
            emit File(what, data);
        } else {
            revert("Safebox/file-unrecognized-param");
        }
    }

    /*//////////////////////////////////
            Custodian Interfaces
    //////////////////////////////////*/

    /**
     * @notice Check if an address has `owner` access on this contract.
     * @param usr The user address.
     * @return Whether `usr` is a ward or not.
     */
    function isOwner(address usr) external view returns (bool) {
        return wards[usr] == 1;
    }

    /**
     * @notice Check if an address has `custodian` access on this contract.
     * @param usr The user address.
     * @return Whether `usr` is a ward or not.
     */
    function isCustodian(address usr) external view returns (bool) {
        return custodians[usr] == 1;
    }

    /**
     * @notice Adds a new custodian to this contract.
     * @param usr The user address.
     */
    function addCustodian(address usr) external onlyCustodian {
        custodians[usr] = 1;
        emit AddCustodian(usr);
    }

    /**
     * @notice Removes a custodian from this contract.
     * @param usr The user address.
     */
    function removeCustodian(address usr) external onlyCustodian {
        custodians[usr] = 0;
        emit RemoveCustodian(usr);
    }

    /**
     * @notice Approves the change in the recipient.
     * @dev Reverts if `pendingRecipient` has not been set or if `_recipient` does not match it.
     * @param _recipient The new recipient being approved.
     */
    function approveChangeRecipient(address _recipient) external {
        require(custodians[msg.sender] == 1, "Safebox/not-custodian");
        require(pendingRecipient != address(0) && pendingRecipient == _recipient, "Safebox/recipient-mismatch");

        recipient = _recipient;
        pendingRecipient = address(0);

        emit RecipientChange(_recipient);
    }
}

interface VatLike {
    function live() external view returns (uint256);
}

interface ERC20Like {
    function transfer(address to, uint256 amt) external returns (bool);

    function transferFrom(address from, address to, uint256 amt) external returns (bool);

    function balanceOf(address usr) external view returns (uint256);
}
