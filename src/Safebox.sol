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
 * @title A safebox for digital assets.
 * The `owner` is in full control of how much and when it can send assets to `recipient`.
 * The `custodian` cooperation is required whenever the `owner` wants to update the `recipient`.
 */
contract Safebox {
    /// @notice The contract owner.
    address public immutable owner;

    /// @notice The contract custodian.
    address public immutable custodian;

    /// @notice The recipient for the assets held in this contract.
    address public recipient;

    /// @notice Reference to the new recipient when it is to be changed.
    address public pendingRecipient;

    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. The supported values are: "recipient".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice The recipient has been sucessfully changed.
     * @param recipient The new recipient address.
     */
    event RecipientChange(address indexed recipient);
    /**
     * @notice A deposit was made into the safebox.
     * @param token The token deposited.
     * @param amount The amount deposited.
     */
    event Deposit(address indexed token, uint256 amount);
    /**
     * @notice A withdrawal was made by the owner.
     * @param token The token withdrawn.
     * @param amount The amount withdrawn.
     */
    event Withdraw(address indexed token, uint256 amount);

    /**
     * @param _owner The safebox owner.
     * @param _custodian The safebox custodian.
     * @param _recipient The recipient for assets in the safebox.
     */
    constructor(address _owner, address _custodian, address _recipient) {
        require(_recipient != address(0), "Safebox/invalid-recipient");

        owner = _owner;
        custodian = _custodian;
        recipient = _recipient;
    }

    /*//////////////////////////////////
             Safebox Operation
    //////////////////////////////////*/

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. `"recipient"`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external {
        require(owner == msg.sender, "Safebox/not-owner");

        if (what == "recipient") {
            require(data != address(0), "Safebox/invalid-recipient");
            pendingRecipient = data;
            emit File(what, data);
        } else {
            revert("Safebox/file-unrecognized-param");
        }
    }

    /**
     * @notice Approves the change in the recipient.
     * @dev Reverts if `previousRecipient` has not been set or if `_recipient` does not match it.
     * @param _recipient The new recipient being approved.
     */
    function approveChangeRecipient(address _recipient) external {
        require(msg.sender == custodian, "Safebox/not-custodian");
        require(pendingRecipient != address(0) && pendingRecipient == _recipient, "Safebox/recipient-mismatch");

        recipient = _recipient;
        pendingRecipient = address(0);

        emit RecipientChange(_recipient);
    }

    /**
     * @notice Deposits ERC20-like tokens into this contract.
     * @param token The token to be deposited.
     * @param amount The amount of tokens.
     */
    function deposit(address token, uint256 amount) external {
        _safeTransferFrom(token, msg.sender, address(this), amount);
        emit Deposit(token, amount);
    }

    /**
     * @notice Withdraws ERC20-like tokens from this contract.
     * @param token The token to be withdrawn.
     * @param amount The amount of tokens.
     */
    function withdraw(address token, uint256 amount) external {
        require(owner == msg.sender, "Safebox/not-owner");

        _safeTransfer(token, recipient, amount);
        emit Withdraw(token, amount);
    }

    /**
     * @dev Handles `transferFrom` for tokens with non-standard ERC-20 implementations.
     * See https://github.com/d-xo/weird-erc20
     * @param from The origin address.
     * @param to The destination address.
     * @param amount The amount to be transfered.
     */
    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory result) = token.call(
            abi.encodeWithSelector(ERC20Like(address(0)).transferFrom.selector, from, to, amount)
        );
        require(success && (result.length == 0 || abi.decode(result, (bool))), "Safebox/token-transfer-from-failed");
    }

    /**
     * @dev Handles `transfer` for tokens with non-standard ERC-20 implementations.
     * See https://github.com/d-xo/weird-erc20
     * @param to The destination address.
     * @param amount The amount to be transfered.
     */
    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory result) = token.call(
            abi.encodeWithSelector(ERC20Like(address(0)).transfer.selector, to, amount)
        );
        require(success && (result.length == 0 || abi.decode(result, (bool))), "Safebox/token-transfer-failed");
    }
}

interface ERC20Like {
    function transfer(address to, uint256 amt) external returns (bool);

    function transferFrom(address from, address to, uint256 amt) external returns (bool);

    function balanceOf(address usr) external view returns (uint256);
}
