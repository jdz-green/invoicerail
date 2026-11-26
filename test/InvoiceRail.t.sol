// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {InvoiceRail, IERC20} from "../src/InvoiceRail.sol";

contract MockToken is IERC20 {
    string public name = "Test USD8";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    bool public returnsNothing;

    function setReturnsNothing(bool v) external { returnsNothing = v; }
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        if (returnsNothing) { assembly { return(0, 0) } }
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "balance");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (returnsNothing) { assembly { return(0, 0) } }
        return true;
    }
}

contract InvoiceRailTest is Test {
    InvoiceRail rail;
    MockToken token;
    address merchant = address(0xA11CE);
    address payer = address(0xB0B);
    bytes32 constant ID = keccak256("invoice-1");
    uint128 constant AMOUNT = 250e18;
    uint64 due;

    function setUp() public {
        token = new MockToken();
        rail = new InvoiceRail(IERC20(address(token)));
        due = uint64(block.timestamp + 7 days);
        token.mint(payer, 1_000e18);
        vm.prank(payer);
        token.approve(address(rail), type(uint256).max);
    }

    function test_createAndPayInFull() public {
        vm.prank(merchant);
        rail.createInvoice(ID, AMOUNT, due);

        vm.prank(payer);
        rail.pay(ID, AMOUNT);

        (, uint128 paid,,, ,) = rail.invoices(ID);
        assertEq(paid, AMOUNT);
        assertEq(token.balanceOf(address(rail)), AMOUNT);
        assertEq(rail.remaining(ID), 0);
    }

    function test_partialPaymentsUntilSettled() public {
        vm.prank(merchant);
        rail.createInvoice(ID, AMOUNT, due);

        vm.startPrank(payer);
        rail.pay(ID, 100e18);
        assertEq(rail.remaining(ID), 150e18);
        rail.pay(ID, 150e18);
        vm.stopPrank();

        assertEq(rail.remaining(ID), 0);
        vm.prank(payer);
        vm.expectRevert(InvoiceRail.AlreadySettled.selector);
        rail.pay(ID, 1);
    }

    function test_overpaymentRejected() public {
        vm.prank(merchant);
        rail.createInvoice(ID, AMOUNT, due);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(InvoiceRail.Overpayment.selector, AMOUNT));
        rail.pay(ID, AMOUNT + 1);
    }

    function test_paymentAfterDueRejected() public {
        vm.prank(merchant);
        rail.createInvoice(ID, AMOUNT, due);
        vm.warp(due + 1);
        vm.prank(payer);
        vm.expectRevert(InvoiceRail.PastDue.selector);
        rail.pay(ID, 1e18);
    }

    function test_merchantWithdrawsPartialThenRest() public {
        vm.prank(merchant);
        rail.createInvoice(ID, AMOUNT, due);

        vm.prank(payer);
        rail.pay(ID, 100e18);
        vm.prank(merchant);
        rail.withdraw(ID);
        assertEq(token.balanceOf(merchant), 100e18);

        vm.prank(payer);
        rail.pay(ID, 150e18);
        vm.prank(merchant);
        rail.withdraw(ID);
        assertEq(token.balanceOf(merchant), AMOUNT);
    }

    function test_onlyMerchantCanWithdrawOrCancel() public {
        vm.prank(merchant);
        rail.createInvoice(ID, AMOUNT, due);
        vm.prank(payer);
        rail.pay(ID, 10e18);

        vm.prank(payer);
        vm.expectRevert(InvoiceRail.NotMerchant.selector);
        rail.withdraw(ID);

        vm.warp(due + 1);
        vm.prank(payer);
        vm.expectRevert(InvoiceRail.NotMerchant.selector);
        rail.cancel(ID);
    }

    function test_cancelOnlyAfterDueAndStopsPayments() public {
        vm.prank(merchant);
        rail.createInvoice(ID, AMOUNT, due);
        vm.prank(merchant);
        vm.expectRevert(InvoiceRail.NotPastDue.selector);
        rail.cancel(ID);

        vm.warp(due + 1);
        vm.prank(merchant);
        rail.cancel(ID);

        vm.prank(payer);
        vm.expectRevert(InvoiceRail.Cancelled.selector);
        rail.pay(ID, 1e18);
    }

    function test_tokenThatReturnsNothingIsAccepted() public {
        token.setReturnsNothing(true);
        vm.prank(merchant);
        rail.createInvoice(ID, AMOUNT, due);
        vm.prank(payer);
        rail.pay(ID, AMOUNT);
        assertEq(token.balanceOf(address(rail)), AMOUNT);
    }

    function test_unknownInvoiceReverts() public {
        vm.prank(payer);
        vm.expectRevert(InvoiceRail.UnknownInvoice.selector);
        rail.pay(keccak256("nope"), 1);
    }

    function test_zeroAmountRejected() public {
        vm.prank(merchant);
        vm.expectRevert(InvoiceRail.ZeroAmount.selector);
        rail.createInvoice(ID, 0, due);
    }

    function test_dueInPastRejected() public {
        vm.prank(merchant);
        vm.expectRevert(InvoiceRail.DueInPast.selector);
        rail.createInvoice(ID, 1, uint64(block.timestamp));
    }

    function test_duplicateIdRejected() public {
        vm.startPrank(merchant);
        rail.createInvoice(ID, AMOUNT, due);
        vm.expectRevert(InvoiceRail.InvoiceExists.selector);
        rail.createInvoice(ID, 1, due);
        vm.stopPrank();
    }
}
