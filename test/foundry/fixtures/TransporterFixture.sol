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
    L1_CHAIN_ID,
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
    uint256 public l1ChainId;
    HubTransporter public hubTransporter;
    SpokeTransporter[] public spokeTransporters;
    mapping(uint256 => Transporter) public transporters;
    mapping(uint256 => address) public hubConnectors;
    mapping(uint256 => address) public spokeConnectors;

    function deployTransporters(uint256 _l1ChainId, uint256[] memory chainIds) public virtual {
        normalizeNonce(chainIds);
        l1ChainId = _l1ChainId;
        deployHubTransporter(_l1ChainId);

        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == _l1ChainId) continue;
            deploySpokeTransporter(_l1ChainId, chainIds[i]);
            deployConnectors(_l1ChainId, chainIds[i], address(hubTransporter), address(spokeTransporters[i - 1]));
        }
    }

    function deployHubTransporter(uint256 _l1ChainId) public broadcastOn(_l1ChainId) {
        hubTransporter = new HubTransporter(
            RELAY_WINDOW,
            MAX_TRANSPORT_FEE_ABSOLUTE,
            MAX_TRANSPORT_FEE_BPS
        );

        transporters[_l1ChainId] = Transporter(payable(address(hubTransporter)));
    }

    function deploySpokeTransporter(uint256 _l1ChainId, uint256 spokeChainId) public broadcastOn(spokeChainId) {
        SpokeTransporter spokeTransporter = new SpokeTransporter(_l1ChainId);
        transporters[spokeChainId] = spokeTransporter;
        spokeTransporters.push(spokeTransporter);
    }

    function deployConnectors(
        uint256 _l1ChainId,
        uint256 spokeChainId,
        address hubTarget,
        address spokeTarget
    )
        public
        crossChainBroadcast
    {
        OPStackConfig memory opStackConfig = ExternalContracts.getOpStackConfig(spokeChainId);

        on(_l1ChainId);
        L1OptimismConnector l1OptimismConnector = new L1OptimismConnector(
            opStackConfig.l1CrossDomainMessenger,
            opStackConfig.defaultGasLimit
        );

        on(spokeChainId);
        L2OptimismConnector l2OptimismConnector = new L2OptimismConnector(
            opStackConfig.l2CrossDomainMessenger,
            opStackConfig.defaultGasLimit
        );

        on(_l1ChainId);
        l1OptimismConnector.initialize(hubTarget, address(l2OptimismConnector));

        on(spokeChainId);
        l2OptimismConnector.initialize(spokeTarget, address(l1OptimismConnector));

        // Save addresses to state
        hubConnectors[spokeChainId] = address(l1OptimismConnector);
        spokeConnectors[spokeChainId] = address(l2OptimismConnector);
    }

    function normalizeNonce(uint256[] memory chainIds) public crossChainBroadcast {
        uint256 highestNonce = 0;
        on(chainIds[0]);
        (,address msgSender,) = vm.readCallers();
        for (uint256 i = 0; i < chainIds.length; i++) {
            on(chainIds[i]);

            uint256 nonce = vm.getNonce(msgSender);
            if (nonce > highestNonce) {
                highestNonce = nonce;
            }
        }
        for (uint256 i = 0; i < chainIds.length; i++) {
            on(chainIds[i]);
            uint256 nonce = vm.getNonce(msgSender);
            for (uint256 j = nonce; j < highestNonce; j++) {
                payable(address(0)).transfer(0);
            }
        }
    }
}

contract ReturnMessageSender {
    function msgSender() public view returns (address) {
        return msg.sender;
    }
}
