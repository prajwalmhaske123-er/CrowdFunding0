// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CrowdFunding.sol";

/// @title DeployCrowdFunding — Deployment script for the CrowdFunding contract.
/// @notice Run with: forge script script/deploy.s.sol:DeployCrowdFunding --rpc-url <RPC_URL> --private-key <KEY> --broadcast
contract DeployCrowdFunding is Script {
    function run() external returns (CrowdFunding crowdFunding) {
        vm.startBroadcast();
        crowdFunding = new CrowdFunding();
        vm.stopBroadcast();
    }
}
