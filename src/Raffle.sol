// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// -  imports
// import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFConsumerBaseV2Plus} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
// import {VRFV2PlusClient} from "@chainlink/contracts/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {VRFV2PlusClient} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

// - NatSpec docs
/**
 * @title A sample Raffle Contract
 * @author deniyaldanidan
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // - custom-errors
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__RaffleUpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState,
        bool timeHasPassed
    );

    // - Type Declarations
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    // - state variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    /**  @dev duration of the lottery in seconds */
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    /** @dev timestamp the lottery is started */
    uint256 private s_lastTimeStamp;
    address payable[] private s_players; // payable address array
    address private s_recentWinner;
    RaffleState private s_raffeState;

    // - events
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffeState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, Raffle__SendMoreToEnterRaffle());
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffeState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // ! It is customary to emit an **event** every time we perform a state modification.
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that the chainlink nodes will call to see if the lottery is ready to have a winner picked.
     ** The Following should be true:
     * ? The time interval has passed between the raffle runs
     * ? The lottery is open
     * ? The contract has players
     * ? The contract has ETH
     * ? Implicitly, your subscription has Link
     * @param - ignored
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = s_raffeState == RaffleState.OPEN;
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasPlayers && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    // 1. Get a Random number
    // 2. Use Random number to pick a player
    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */) external {
        // if ((block.timestamp - s_lastTimeStamp) < i_interval) {
        //     revert();
        // }
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__RaffleUpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffeState),
                (block.timestamp - s_lastTimeStamp) >= i_interval
            );
        }
        s_raffeState = RaffleState.CALCULATING;
        // get a random number
        // 1. Request RNG
        // 2. Get RNG
        VRFV2PlusClient.RandomWordsRequest
            memory randomWordsReq = VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false}) // now it will use LINK
                )
            });
        // s_vrfCoordinator.requestRandomWords(randomWordsReq);
        uint256 requestId = s_vrfCoordinator.requestRandomWords(randomWordsReq);
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] calldata randomWords
    ) internal override {
        uint256 indexOfwinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfwinner];
        s_recentWinner = recentWinner;

        s_raffeState = RaffleState.OPEN; // turn raffle state open
        s_players = new address payable[](0); // empty out the players array
        s_lastTimeStamp = block.timestamp; //  reset the last_timestamp to now
        emit WinnerPicked(s_recentWinner);

        (bool success, ) = recentWinner.call{value: address(this).balance}(""); // transfer the funds to the winner
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * getter function for entrance-fee
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffeState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
