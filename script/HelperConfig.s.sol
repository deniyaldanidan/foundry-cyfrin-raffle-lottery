// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {VRFCoordinatorV2_5Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    /* VRF Mock Values */
    uint96 public MOCK_BASE_FEE = 0.25 ether;
    uint96 public MOCK_GAS_PRICE_LINK = 1e9;
    // LINK/ETH price
    int256 public MOCK_WEI_PER_UINT_LINK = 4e15;

    // CHAIN_ID's
    uint256 public constant ETH_SEPOLIA_CHAINID = 11155111;
    uint256 public constant LOCAL_CHAINID = 31337;
}

contract HelperConfig is Script, CodeConstants {
    error HelperConfig__InvalidChainID();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        address account;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAINID] = getSepoliaEthConfig();
    }

    function getConfigByChainId(
        uint256 chainID
    ) public returns (NetworkConfig memory) {
        if (networkConfigs[chainID].vrfCoordinator != address(0)) {
            return networkConfigs[chainID];
        } else if (chainID == LOCAL_CHAINID) {
            return getOrCreateLocalETHConfig();
        } else {
            revert HelperConfig__InvalidChainID();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 30, // 30 seconds
                vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                callbackGasLimit: 500000, // 500,000 gas
                subscriptionId: 82496430388298082863816507813822001486765419493645762777596258071407158752944,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
                account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 /* Enter your wallet's public address here. The Address enter here is a default anvil account. Don't rely on that */
            });
    }

    function getOrCreateLocalETHConfig() public returns (NetworkConfig memory) {
        // check if we already set an active network cofig
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock = new VRFCoordinatorV2_5Mock(
                MOCK_BASE_FEE,
                MOCK_GAS_PRICE_LINK,
                MOCK_WEI_PER_UINT_LINK
            );
        LinkToken linkTokenMock = new LinkToken();
        vm.stopBroadcast();
        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30, // 30 seconds
            vrfCoordinator: address(vrfCoordinatorV2_5Mock),
            // we have to fix this
            subscriptionId: 0,
            // doesn't matter for a mock
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500000, // 500,000 gas
            link: address(linkTokenMock),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 // Default sender-address from Foundry forge-std/src/Base.sol
        });
        return localNetworkConfig;
    }
}
