// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {InvoiceRail, IERC20} from "../src/InvoiceRail.sol";

/// @notice One readable end-to-end walkthrough, used as the demo transcript.
contract LifecycleTest is Test {
    InvoiceRail rail;
    MockToken token;
    address merchant = address(0xA11CE);
    address payer = address(0xB0B);

    function setUp() public {
        token = new MockToken();
        rail = new InvoiceRail(IERC20(address(token)));
        token.mint(payer, 1_000e18);
        vm.prank(payer);
        token.approve(address(rail), type(uint256).max);
    }

    function test_fullInvoiceLifecycle() public {
        bytes32 id = keccak256("inv-1");
        vm.prank(merchant);
        rail.createInvoice(id, 250e18, uint64(block.timestamp + 7 days));
        console.log("1. invoice created: 250 tUSD8 due in 7 days");

        vm.prank(payer);
        rail.pay(id, 100e18);
        console.log("2. paid 100 -> remaining", rail.remaining(id) / 1e18);

        vm.prank(payer);
        rail.pay(id, 150e18);
        console.log("3. paid 150 -> remaining", rail.remaining(id));

        vm.prank(merchant);
        rail.withdraw(id);
        console.log("4. merchant balance", token.balanceOf(merchant) / 1e18);

        bytes32 id2 = keccak256("inv-2");
        vm.prank(merchant);
        rail.createInvoice(id2, 40e18, uint64(block.timestamp + 1));
        vm.warp(block.timestamp + 2);
        vm.prank(merchant);
        rail.cancel(id2);
        console.log("5. expired invoice cancelled");
    }
}

contract MockToken {
    string public name = "Mock tUSD8";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "balance");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
