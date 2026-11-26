// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {InvoiceRail, IERC20} from "../src/InvoiceRail.sol";

/// @notice A full InvoiceRail flow against the live Aevum testnet state, using a local mock token so
///         the transcript can be produced without funding a wallet. No broadcast.
/// Usage: forge script script/Demo.s.sol --fork-url https://rpc-test.qday.info
contract Demo is Script {
    function run() external {
        vm.startPrank(address(0xA11CE));
        MockUSD8 usd = new MockUSD8();
        InvoiceRail rail = new InvoiceRail(IERC20(address(usd)));
        vm.stopPrank();

        address merchant = address(0xA11CE);
        address payer = address(0xB0B);
        uint64 due = uint64(block.timestamp + 7 days);
        bytes32 id = keccak256("invoice-demo-1");

        usd.mint(payer, 1_000e18);
        vm.prank(payer);
        usd.approve(address(rail), type(uint256).max);

        vm.prank(merchant);
        rail.createInvoice(id, 250e18, due);
        console.log("1. invoice created for 250 tUSD8, due in 7 days");

        vm.prank(payer);
        rail.pay(id, 100e18);
        console.log("2. payer paid 100; remaining:", rail.remaining(id) / 1e18);

        vm.prank(payer);
        rail.pay(id, 150e18);
        console.log("3. payer paid the last 150; remaining:", rail.remaining(id));

        vm.prank(merchant);
        rail.withdraw(id);
        console.log("4. merchant withdrew:", usd.balanceOf(merchant) / 1e18);

        bytes32 id2 = keccak256("invoice-demo-2");
        vm.prank(merchant);
        rail.createInvoice(id2, 50e18, uint64(block.timestamp + 1));
        vm.warp(block.timestamp + 2);
        vm.prank(merchant);
        rail.cancel(id2);
        console.log("5. second invoice expired and was cancelled by the merchant");
    }
}

contract MockUSD8 {
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
