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
    Safebox safebox;
    ERC20 usdx = new ERC20("USDX", "USDX", 18);

    FakeVatLiveness vat = new FakeVatLiveness();
    address owner = address(this);
    address custodian = address(0x1337);
    address recipient = address(0x2448);
    address anyone = address(0x3559);

    function setUp() public {
        safebox = new Safebox(address(vat), address(usdx), owner, custodian, recipient);
    }

    function testConstructorRevertWhenRecipientIsInvalid() public {
        vm.expectRevert("Safebox/invalid-recipient");
        new Safebox(address(vat), address(usdx), owner, custodian, address(0));
    }

    function testGiveRightPermissionsUponCreation() public {
        vm.expectEmit(true, false, false, false);
        emit Rely(owner);
        vm.expectEmit(true, false, false, false);
        emit AddCustodian(custodian);
        safebox = new Safebox(address(vat), address(usdx), owner, custodian, recipient);

        assertEq(safebox.wards(owner), 1, "Owner was not relied");
        assertEq(safebox.custodians(custodian), 1, "Custodian was not hoped");
    }

    function testRelyDeny() public {
        assertEq(safebox.wards(address(1)), 0, "Pre-condition failed: ward already set");

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Rely(address(1));

        safebox.rely(address(1));

        assertEq(safebox.wards(address(1)), 1, "Post-condition failed: ward not set");

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Deny(address(1));

        safebox.deny(address(1));

        assertEq(safebox.wards(address(1)), 0, "Pre-condition failed: ward not removed");
    }

    function testAddRemoveCustodian() public {
        vm.startPrank(custodian);

        assertEq(safebox.custodians(address(1)), 0, "Pre-condition failed: ward already set");

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit AddCustodian(address(1));

        safebox.addCustodian(address(1));

        assertEq(safebox.custodians(address(1)), 1, "Post-condition failed: ward not set");

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit RemoveCustodian(address(1));

        safebox.removeCustodian(address(1));

        assertEq(safebox.custodians(address(1)), 0, "Pre-condition failed: ward not removed");
    }

    function testOwnerCanRequestWithdrawal() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        vm.expectEmit(true, true, false, true);
        emit RequestWithdrawal(address(this), amount);

        safebox.requestWithdrawal(amount);
    }

    function testRevertRequestWithdrawalOfZero() public {
        vm.expectRevert("Safebox/invalid-amount");
        safebox.requestWithdrawal(0);
    }

    function testRevertRequestMultipleWithdrawals() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        safebox.requestWithdrawal(amount);

        vm.expectRevert("Safebox/pending-withdrawal");
        safebox.requestWithdrawal(amount + 1);
    }

    function testRevertRequestWithdrawalWhenNotOwner() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);
        assertEq(usdx.balanceOf(address(safebox)), amount);

        vm.expectRevert("Safebox/not-ward");

        vm.startPrank(anyone);
        safebox.requestWithdrawal(amount);
    }

    function testAnyoneCanRequestWithdrawalWhenVatIsNotLive() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        vat.cage();

        vm.expectEmit(true, false, false, true);
        emit RequestWithdrawal(anyone, amount);

        vm.startPrank(anyone);
        safebox.requestWithdrawal(amount);
    }

    function testOwnerCanCancelWithdrawal() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        assertEq(usdx.balanceOf(address(safebox)), amount, "Pre-condition failed: bad safebox balance");
        assertEq(usdx.balanceOf(recipient), 0, "Pre-condition failed: recipient balance not zero");

        safebox.requestWithdrawal(amount);

        vm.expectEmit(true, false, false, true);
        emit CancelWithdrawal(address(this), amount);

        safebox.cancelWithdrawal();

        assertEq(usdx.balanceOf(address(safebox)), amount, "Post-condition failed: bad safebox balance");
        assertEq(usdx.balanceOf(recipient), 0, "Post-condition failed: recipient balance not zero");
    }

    function testRevertCancelWithdrawalAfterCage() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        safebox.requestWithdrawal(amount);
        vat.cage();

        vm.expectRevert("Safebox/vat-not-live");
        safebox.cancelWithdrawal();
    }

    function testRevertRevertCancelWithdrawalWhenNotRequested() public {
        vm.expectRevert("Safebox/no-pending-withdrawal");
        safebox.cancelWithdrawal();
    }

    function testCustodianCanExecuteFullWithdrawalImmediately() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        assertEq(usdx.balanceOf(address(safebox)), amount, "Pre-condition failed: bad safebox balance");
        assertEq(usdx.balanceOf(recipient), 0, "Pre-condition failed: recipient balance not zero");

        safebox.requestWithdrawal();

        vm.expectEmit(true, true, false, true);
        emit ExecuteWithdrawal(custodian, recipient, amount);

        vm.startPrank(custodian);
        safebox.executeWithdrawal();

        assertEq(usdx.balanceOf(address(safebox)), 0, "Post-condition failed: invalid safebox balance");
        assertEq(usdx.balanceOf(recipient), amount, "Post-condition failed: invalid recipient balance");
    }

    function testCustodianCanExecuteWithdrawalImmediately() public {
        uint256 totalAmount = 123;
        uint256 withdrawalAmount = 23;
        usdx.mint(address(safebox), totalAmount);

        assertEq(usdx.balanceOf(address(safebox)), totalAmount, "Pre-condition failed: bad safebox balance");
        assertEq(usdx.balanceOf(recipient), 0, "Pre-condition failed: recipient balance not zero");

        safebox.requestWithdrawal(withdrawalAmount);

        vm.expectEmit(true, true, false, true);
        emit ExecuteWithdrawal(custodian, recipient, withdrawalAmount);

        vm.startPrank(custodian);
        safebox.executeWithdrawal();

        assertEq(
            usdx.balanceOf(address(safebox)),
            totalAmount - withdrawalAmount,
            "Post-condition failed: invalid safebox balance"
        );
        assertEq(usdx.balanceOf(recipient), withdrawalAmount, "Post-condition failed: invalid recipient balance");
    }

    function testAnyoneCanExecuteWithdrawalAfterTimelock() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        assertEq(usdx.balanceOf(address(safebox)), amount, "Pre-condition failed: bad safebox balance");
        assertEq(usdx.balanceOf(recipient), 0, "Pre-condition failed: recipient balance not zero");

        safebox.requestWithdrawal(amount);
        skip(safebox.WITHDRAWAL_TIMELOCK() + 1);

        vm.expectEmit(true, true, false, true);
        emit ExecuteWithdrawal(anyone, recipient, amount);

        vm.startPrank(anyone);
        safebox.executeWithdrawal();

        assertEq(usdx.balanceOf(address(safebox)), 0, "Post-condition failed: invalid safebox balance");
        assertEq(usdx.balanceOf(recipient), amount, "Post-condition failed: invalid recipient balance");
    }

    function testAnyoneCanExecuteWithdrawalImmediatelyAfterCage() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        assertEq(usdx.balanceOf(address(safebox)), amount, "Pre-condition failed: bad safebox balance");
        assertEq(usdx.balanceOf(recipient), 0, "Pre-condition failed: recipient balance not zero");

        safebox.requestWithdrawal(amount);
        vat.cage();

        vm.expectEmit(true, true, false, true);
        emit ExecuteWithdrawal(anyone, recipient, amount);

        vm.startPrank(anyone);
        safebox.executeWithdrawal();

        assertEq(usdx.balanceOf(address(safebox)), 0, "Post-condition failed: invalid safebox balance");
        assertEq(usdx.balanceOf(recipient), amount, "Post-condition failed: invalid recipient balance");
    }

    function testRevertExecuteWithdrawalBeforeTimelock() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        assertEq(usdx.balanceOf(address(safebox)), amount, "Pre-condition failed: bad safebox balance");
        assertEq(usdx.balanceOf(recipient), 0, "Pre-condition failed: recipient balance not zero");

        safebox.requestWithdrawal(amount);
        skip(safebox.WITHDRAWAL_TIMELOCK() - 1);

        vm.expectRevert("Safebox/active-timelock");
        vm.startPrank(anyone);
        safebox.executeWithdrawal();
    }

    function testRevertExecuteWithdrawalWhenNotRequested() public {
        vm.expectRevert("Safebox/no-pending-withdrawal");
        safebox.executeWithdrawal();
    }

    function testRevertExecuteADeniedWithdrawal() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        assertEq(usdx.balanceOf(address(safebox)), amount, "Pre-condition failed: bad safebox balance");
        assertEq(usdx.balanceOf(recipient), 0, "Pre-condition failed: recipient balance not zero");

        safebox.requestWithdrawal(amount);

        vm.expectEmit(true, true, false, true);
        emit DenyWithdrawal(custodian, amount);

        vm.prank(custodian);
        safebox.denyWithdrawal();

        skip(safebox.WITHDRAWAL_TIMELOCK() + 1);

        vm.expectRevert("Safebox/no-pending-withdrawal");
        safebox.executeWithdrawal();
    }

    function testRevertDenyWithdrawalWhenNotRequested() public {
        vm.expectRevert("Safebox/no-pending-withdrawal");
        vm.prank(custodian);
        safebox.denyWithdrawal();
    }

    function testRevertDenyWithdrawalAfterTimelock() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);

        safebox.requestWithdrawal(amount);

        skip(safebox.WITHDRAWAL_TIMELOCK() + 1);

        vm.expectRevert("Safebox/timelock-expired");
        vm.prank(custodian);
        safebox.denyWithdrawal();
    }

    function testRevertDenyWithdrawalAfterCage() public {
        uint256 amount = 123;
        usdx.mint(address(safebox), amount);
        safebox.requestWithdrawal(amount);
        vat.cage();

        vm.expectRevert("Safebox/vat-not-live");
        vm.prank(custodian);
        safebox.denyWithdrawal();
    }

    function testRevertDenyWithdrawalWhenNotCustodian() public {
        vm.expectRevert("Safebox/not-custodian");

        vm.prank(anyone);
        safebox.denyWithdrawal();
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

    function testRevertChangeRecipientWhenNotCustodian() public {
        address newRecipient = address(0xd34d);
        safebox.file("recipient", newRecipient);

        assertEq(safebox.pendingRecipient(), newRecipient, "Post-condition: failed to set pending recipient");

        vm.expectRevert("Safebox/not-custodian");

        vm.prank(address(0xd34d));
        safebox.approveChangeRecipient(newRecipient);
    }

    function testRevertChangeRecipientWithMismatchingAddresses() public {
        address newRecipient = address(0xd34d);
        safebox.file("recipient", newRecipient);

        assertEq(safebox.pendingRecipient(), newRecipient, "Post-condition: failed to set pending recipient");

        vm.expectRevert("Safebox/recipient-mismatch");

        vm.prank(address(custodian));
        safebox.approveChangeRecipient(address(0x1234));
    }

    function testRevertChangeRecipientAfterCage() public {
        address newRecipient = address(0xd34d);

        vat.cage();

        vm.expectRevert("Safebox/vat-not-live");
        safebox.file("recipient", newRecipient);
    }

    function testRevertApproveChangeRecipientAfterCage() public {
        address newRecipient = address(0xd34d);
        safebox.file("recipient", newRecipient);

        vat.cage();

        vm.expectRevert("Safebox/vat-not-live");
        vm.prank(address(custodian));
        safebox.approveChangeRecipient(newRecipient);
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddCustodian(address indexed usr);
    event RemoveCustodian(address indexed usr);
    event File(bytes32 indexed what, address data);
    event RecipientChange(address indexed recipient);
    event RequestWithdrawal(address indexed sender, uint256 amount);
    event ExecuteWithdrawal(address indexed sender, address indexed recipient, uint256 amount);
    event CancelWithdrawal(address indexed sender, uint256 amount);
    event DenyWithdrawal(address indexed sender, uint256 amount);
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

contract FakeVatLiveness {
    uint256 public live = 1;

    function cage() external {
        live = 0;
    }
}
