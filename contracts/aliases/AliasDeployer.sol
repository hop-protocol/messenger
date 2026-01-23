// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ICrossChainFees.sol";
import "../shared-solidity/OverridableChainId.sol";
import "./AliasFactory.sol";

interface IAliasFactory {
    function deployAlias(uint256 sourceChainId, address sourceAddress, address aliasDispatcher) external payable;
    function deployAliasDispatcher(address sourceAddress) external payable;
}

/// @dev AliasDeployer calls the AliasFactory's to deploy aliases on multiple chains.
contract AliasDeployer is OverridableChainId, Ownable, ICrossChainFees {
    uint256 public constant crossChainMessageFee = 0;
    // address for factory or factory connector
    mapping(uint256 => address) public aliasFactoryForChainId;

    function deployAliases(
        uint256 sourceChainId,
        address sourceAddress,
        uint256[] calldata aliasChainIds
    )
        external
        payable
    {
        uint256 thisChainId = getChainId();

        IAliasFactory aliasFactory = IAliasFactory(aliasFactoryForChainId[sourceChainId]);
        uint256 messageFee = thisChainId == sourceChainId ? 0 : crossChainMessageFee;
        aliasFactory.deployAliasDispatcher{value: messageFee}(sourceAddress);
        address aliasDispatcher = calculateAliasDispatcherAddress(sourceAddress);

        for(uint256 i = 0; i < aliasChainIds.length; i++) {
            uint256 chainId = aliasChainIds[i];
            deployAlias(chainId, sourceChainId, sourceAddress, aliasDispatcher);
        }

        // ToDo: Refund excess message fees
    }

    function deployAlias(uint256 chainId, uint256 sourceChainId, address sourceAddress, address aliasDispatcher) public payable {
        address factoryOrConnectorAddress = aliasFactoryForChainId[chainId];
        IAliasFactory factoryOrConnector = IAliasFactory(factoryOrConnectorAddress);
        uint256 messageFee = 0;
        if (chainId != getChainId()) {
            messageFee = ICrossChainFees(factoryOrConnectorAddress).getFee(chainId);
        }
        factoryOrConnector.deployAlias{value: messageFee}(sourceChainId, sourceAddress, aliasDispatcher);
    }

    function setAliasFactoryForChainId(uint256 chainId, address factory) external onlyOwner {
        aliasFactoryForChainId[chainId] = factory;
    }

    function getFee(uint256 chainId) external override view returns (uint256 fee) {
        uint256 thisChainId = getChainId();
        if (chainId == thisChainId) {
            return 0;
        }
        address connector = aliasFactoryForChainId[chainId];
        return ICrossChainFees(connector).getFee(chainId);
    }

    function getAliasFactory() public view returns (address) {
        return aliasFactoryForChainId[getChainId()];
    }

    function calculateAliasAddress(
        uint256 sourceChainId,
        address sourceAddress,
        address aliasDispatcher
    )
        external
        view
        returns (address)
    {
        return AliasFactory(getAliasFactory()).calculateAliasAddress(sourceChainId, sourceAddress, aliasDispatcher);
    }

    function calculateAliasDispatcherAddress(address sourceAddress) public view returns (address) {
        return AliasFactory(getAliasFactory()).calculateAliasDispatcherAddress(sourceAddress);
    }
}
