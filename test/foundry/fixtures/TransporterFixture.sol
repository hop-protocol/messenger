// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {MockConnector} from "../../../contracts/connectors/test/MockConnector.sol";
import {L1OptimismConnector} from "../../../contracts/connectors/external/L1OptimismConnector.sol";
import {L2OptimismConnector} from "../../../contracts/connectors/external/L2OptimismConnector.sol";

import {
    RELAY_WINDOW,
    MAX_TRANSPORT_FEE_ABSOLUTE,
    MAX_TRANSPORT_FEE_BPS,
    HUB_CHAIN_ID,
    SPOKE_CHAIN_ID_0,
    SPOKE_CHAIN_ID_1,
    FULL_POOL_SIZE
} from "../libraries/Constants.sol";
import {ExternalContracts, OPStackConfig} from "../libraries/ExternalContracts.sol";
import {CrossChainTest, Chain} from "../libraries/CrossChainTest.sol";
import {Transporter} from "../../../contracts/transporter/Transporter.sol";
import {HubTransporter} from "../../../contracts/transporter/HubTransporter.sol";
import {SpokeTransporter} from  "../../../contracts/transporter/SpokeTransporter.sol";

contract TransporterFixture is CrossChainTest {
    uint256 public hubChainId;
    uint256[] public spokeChainIds;
    HubTransporter public hubTransporter;
    SpokeTransporter[] public spokeTransporters;
    mapping(uint256 => Transporter) public transporters;
    mapping(uint256 => address) public hubConnectors;
    mapping(uint256 => address) public spokeConnectors;

    function deployTransporters(uint256[] memory chainIds) public virtual {
        uint256 _hubChainId = chainIds[0];
        hubChainId = _hubChainId;

        deployHubTransporter(_hubChainId);

        spokeChainIds = new uint256[](chainIds.length - 1);
        for (uint256 i = 1; i < chainIds.length; i++) {
            spokeChainIds[i - 1] = chainIds[i];
            deploySpokeTransporter(_hubChainId, chainIds[i]);
            deployConnectors(_hubChainId, chainIds[i], address(hubTransporter), address(spokeTransporters[i - 1]));
        }
    }

    function deployHubTransporter(uint256 _hubChainId) public broadcastOn(_hubChainId) {
        hubTransporter = new HubTransporter(
            RELAY_WINDOW,
            MAX_TRANSPORT_FEE_ABSOLUTE,
            MAX_TRANSPORT_FEE_BPS
        );

        transporters[_hubChainId] = Transporter(address(hubTransporter));
    }

    function deploySpokeTransporter(uint256 _hubChainId, uint256 spokeChainId) public broadcastOn(spokeChainId) {
        SpokeTransporter spokeTransporter = new SpokeTransporter(_hubChainId, FULL_POOL_SIZE);
        transporters[spokeChainId] = spokeTransporter;
        spokeTransporters.push(spokeTransporter);
    }

    function deployConnectors(
        uint256 _hubChainId,
        uint256 spokeChainId,
        address hubTarget,
        address spokeTarget
    )
        public
        crossChainBroadcast
    {
        OPStackConfig memory opStackConfig = ExternalContracts.getOpStackConfig(spokeChainId);

        on(_hubChainId);
        L1OptimismConnector l1OptimismConnector = new L1OptimismConnector(
            opStackConfig.l1CrossDomainMessenger,
            opStackConfig.defaultGasLimit
        );

        on(spokeChainId);
        L2OptimismConnector l2OptimismConnector = new L2OptimismConnector(
            opStackConfig.l2CrossDomainMessenger,
            opStackConfig.defaultGasLimit
        );

        on(_hubChainId);
        l1OptimismConnector.initialize(hubTarget, address(l2OptimismConnector));

        on(spokeChainId);
        l2OptimismConnector.initialize(spokeTarget, address(l1OptimismConnector));

        // Save addresses to state
        hubConnectors[spokeChainId] = address(l1OptimismConnector);
        spokeConnectors[spokeChainId] = address(l2OptimismConnector);
    }
}
