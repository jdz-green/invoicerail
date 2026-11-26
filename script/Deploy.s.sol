// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {InvoiceRail, IERC20} from "../src/InvoiceRail.sol";

/// @notice Deploy InvoiceRail against the tUSD8 token on QDay Aevum testnet.
/// Usage (simulation, no broadcast):
///   forge script script/Deploy.s.sol --fork-url https://rpc-test.qday.info
/// Usage (broadcast, needs a funded key):
///   PRIVATE_KEY=0x... forge script script/Deploy.s.sol --rpc-url https://rpc-test.qday.info --broadcast
contract Deploy is Script {
    // tUSD8 on QDay Aevum, found via the explorer token search on 2026-11-26
    address constant TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;

    function run() external returns (InvoiceRail rail) {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        if (pk != 0) vm.startBroadcast(pk);
        rail = new InvoiceRail(IERC20(TUSD8));
        console.log("InvoiceRail deployed at", address(rail));
        console.log("token", TUSD8);
        if (pk != 0) vm.stopBroadcast();
    }
}
