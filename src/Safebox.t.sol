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

import {Test} from "forge-std/Test.sol";
import {ERC20 as ERC20Abstract} from "solmate/tokens/ERC20.sol";
import {Safebox} from "./Safebox.sol";

contract SafeboxTest is Test {
    Safebox internal safebox;
    ERC20 internal usdx = new ERC20("USDX", "USDX", 18);

    address internal owner = address(this);
    address internal custodian = address(0x1337);
    address internal recipient = address(0x2448);

    function setUp() public {
        safebox = new Safebox(owner, custodian, recipient);
    }

    function testConstructorRevertWhenRecipientIsInvalid() public {
        vm.expectRevert("Safebox/invalid-recipient");
        new Safebox(owner, custodian, address(0));
    }

    function testGiveRightPermissionsUponCreation() public {
        safebox = new Safebox(owner, custodian, recipient);

        assertEq(safebox.owner(), owner, "Owner was not relied");
        assertEq(safebox.custodian(), custodian, "Custodian was not hoped");
    }

    function testFuzzAnyoneCanDeposit(address sender) public {
        uint256 amount = 20;
        usdx.mint(sender, amount);

        vm.startPrank(sender);
        usdx.approve(address(safebox), type(uint256).max);

        vm.expectEmit(true, false, false, true);
        emit Deposit(address(usdx), amount);

        assertEq(usdx.balanceOf(address(safebox)), 0, "Pre-condition failed: safebox balance not zero");

        safebox.deposit(address(usdx), amount);

        assertEq(usdx.balanceOf(address(safebox)), amount, "Post-condition failed: invalid safebox balance");
    }

    function testOwnerCanWithdraw() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);
        assertEq(usdx.balanceOf(address(safebox)), amount);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(usdx), amount);

        assertEq(usdx.balanceOf(recipient), 0, "Pre-condition failed: recipient balance not zero");

        safebox.withdraw(address(usdx), amount);

        assertEq(usdx.balanceOf(address(safebox)), 0, "Post-condition failed: invalid safebox balance");
        assertEq(usdx.balanceOf(recipient), amount, "Post-condition failed: invalid recipient balance");
    }

    function testFuzzCannotWithdrawWhenNotOwner(address sender) public {
        vm.assume(sender != owner);

        uint256 amount = 123;
        usdx.mint(address(safebox), amount);
        assertEq(usdx.balanceOf(address(safebox)), amount);

        vm.expectRevert("Safebox/not-owner");

        vm.startPrank(address(sender));
        safebox.withdraw(address(usdx), amount);
    }

    function testChangeRecipient() public {
        address newRecipient = address(0xd34d);
        safebox.file("recipient", newRecipient);

        assertEq(safebox.pendingRecipient(), newRecipient, "Post-condition: failed to set pending recipient");

        vm.prank(address(custodian));
        safebox.approveChangeRecipient(newRecipient);

        assertEq(
            safebox.pendingRecipient(),
            address(0),
            "Post-condition: failed to reset pending recipient after approve"
        );
        assertEq(safebox.recipient(), newRecipient, "Post-condition: failed to set recipient after approve");
    }

    function testRevertChangeRecipientWithInvalidAddress() public {
        vm.expectRevert("Safebox/invalid-recipient");

        safebox.file("recipient", address(0));
    }

    function testReverChangeRecipientWhenNotCustodian() public {
        address newRecipient = address(0xd34d);
        safebox.file("recipient", newRecipient);

        assertEq(safebox.pendingRecipient(), newRecipient, "Post-condition: failed to set pending recipient");

        vm.expectRevert("Safebox/not-custodian");

        vm.prank(address(0xd34d));
        safebox.approveChangeRecipient(newRecipient);
    }

    function testReverChangeRecipientWithMismatchingAddresses() public {
        address newRecipient = address(0xd34d);
        safebox.file("recipient", newRecipient);

        assertEq(safebox.pendingRecipient(), newRecipient, "Post-condition: failed to set pending recipient");

        vm.expectRevert("Safebox/recipient-mismatch");

        vm.prank(address(custodian));
        safebox.approveChangeRecipient(address(0x1234));
    }

    event File(bytes32 indexed what, address data);
    event RecipientChange(address indexed recipient);
    event Deposit(address indexed token, uint256 amount);
    event Withdraw(address indexed token, uint256 amount);
}

contract ERC20 is ERC20Abstract {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20Abstract(name, symbol, decimals) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
