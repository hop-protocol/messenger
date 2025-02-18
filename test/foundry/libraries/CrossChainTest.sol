// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

struct Chain {
    string name;
    uint256 chainId;
    string chainAlias;
    string rpcUrl;
}

contract CrossChainTest is Test {
    mapping(uint256 => uint256) public forkIdForChainId;
    uint256 public currentChainId;
    bool public crossChainBroadcastInProgress;
    uint256 timeToSkip;

    constructor() {
        // set non-standard chains
        setChain(
            "optimism_sepolia", 
            Chain(
                "Optimism Sepolia",
                11155420,
                "optimism_sepolia",
                vm.envString("RPC_ENDPOINT_OPTIMISM_SEPOLIA")
            )
        );
        setChain(
            "base_sepolia", 
            Chain(
                "Base Sepolia",
                84532,
                "base_sepolia",
                vm.envString("RPC_ENDPOINT_BASE_SEPOLIA")
            )
        );
        setChain(
            "hop_sepolia", 
            Chain(
                "Hop Sepolia",
                42069,
                "hop_sepolia",
                vm.envString("RPC_ENDPOINT_HOP_SEPOLIA")
            )
        );

        // Hacky way to burn forkId 0
        Chain memory chain = getChain("sepolia");
        vm.createFork(chain.rpcUrl);
    }

    modifier broadcastOn(uint256 chainId) {
        uint256 _cachedChainId = currentChainId;
        _on(chainId);
        _;
        if (_cachedChainId != 0) {
            _on(_cachedChainId);
        } else {
            stopBroadcast();
            currentChainId = 0;
        }
    }

    modifier crossChainBroadcast() {
        uint256 _cachedChainId = currentChainId;
        crossChainBroadcastInProgress = true;
        _;
        if (_cachedChainId != 0) {
            _on(_cachedChainId);
        } else if (currentChainId != 0) {
            stopBroadcast();
            currentChainId = 0;
        }
    }

    function on(uint256 chainId) internal {
        require(crossChainBroadcastInProgress == true, "Not cross chain broadcasting");
        _on(chainId);
    }

    function on(string memory chainAlias) internal {
        require(crossChainBroadcastInProgress == true, "Not cross chain broadcasting");
        Chain memory chain = getChain(chainAlias);
        _on(chain.chainId);
    }

    function _on(uint256 chainId) private {
        if (currentChainId != 0) {
            stopBroadcast();
            currentChainId = 0;
        }

        // if no fork exists, create a new fork
        uint256 forkId = forkIdForChainId[chainId];
        if (forkId == 0) {
            Chain memory chain = getChain(chainId);
            forkId = vm.createFork(chain.rpcUrl);
            forkIdForChainId[chain.chainId] = forkId;
        }

        vm.selectFork(forkId);
        startBroadcast();
        currentChainId = chainId;
        skip(timeToSkip);
    }

    function skipTime(uint256 time) internal {
        timeToSkip += time;
        skip(timeToSkip);
    }

    function startBroadcast() internal virtual {}

    function stopBroadcast() internal virtual {}
}
