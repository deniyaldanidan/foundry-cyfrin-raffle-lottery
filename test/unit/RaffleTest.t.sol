// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;
    address public immutable I_PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    uint256 public constant LOCAL_CHAINID = 31337;

    uint256 private entranceFee;
    uint256 private interval;
    address private vrfCoordinator;
    bytes32 private gasLane;
    uint256 private subscriptionId;
    uint32 private callbackGasLimit;

    event RaffleEntered(address indexed player);

    modifier raffleEnterMod() {
        vm.prank(I_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // changing the test-blockchain timestamp
        vm.roll(block.number + 1); // adding new one-more block to the test-blockchain
        _;
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAINID) {
            return;
        }
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployRaffleContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(I_PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        // assertEq(uint256(raffle.getRaffleState()), 0);
    }

    function testCheckGetEntranceFee() public view {
        assertEq(raffle.getEntranceFee(), entranceFee);
    }

    // #######################################################
    //                  testEnterRaffle
    // #######################################################

    function testRaffleEntranceFeeRevert() public {
        vm.prank(I_PLAYER);
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle{value: 0.005 ether}();
    }

    function testRaffleRecordsPlayerWhenEnter() public {
        // vm.startPrank(I_PLAYER);
        // Arrange
        vm.prank(I_PLAYER);
        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        assertEq(raffle.getPlayer(0), I_PLAYER);
        // Log
        // console.log(raffle.getPlayer(0), I_PLAYER);
        // console.log(address(raffle).balance);
        // vm.stopPrank();
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.prank(I_PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(I_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating()
        public
        raffleEnterMod
    {
        raffle.performUpkeep("");

        // check will it revert when it is CALCULATING
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(I_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    // #######################################################
    //                  testCheckUpKeep
    // #######################################################

    function testCheckUpKeepReturnsFalseIfItHasNoBalance()
        public
        raffleEnterMod
    {
        console.log(
            "Raffle Contract initial balance: ",
            address(raffle).balance
        );
        console.log("Funded by: ", raffle.getPlayer(0));

        // Emptying the balance of raffle contract
        address payable emptyAddress = payable(address(0));
        vm.prank(address(raffle));
        (bool success, ) = emptyAddress.call{value: address(raffle).balance}(
            ""
        );

        if (success == true) {
            console.log(
                "Raffle Contract balance after emptying out: ",
                address(raffle).balance
            );
            (bool upkeepNeeded, ) = raffle.checkUpkeep("");
            assert(!upkeepNeeded);
        }
    }

    function testCheckUpKeepReturnsFalseIfRaffleIsNotOpen()
        public
        raffleEnterMod
    {
        raffle.performUpkeep(""); // this line will close the RAFFLE

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        vm.prank(I_PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsTrueIfAllConditionsPassed()
        public
        raffleEnterMod
    {
        // act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // assert
        assert(upkeepNeeded);
    }

    // #######################################################
    //                  testPerformUpKeep
    // #######################################################

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        raffleEnterMod
    {
        // act | assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // arrange
        uint256 currentBalance = 0;
        uint256 numOfPlayers = 0;
        bool timeHasPassed = true;
        vm.warp(block.timestamp + interval + 1);

        // Act | Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__RaffleUpkeepNotNeeded.selector,
                currentBalance,
                numOfPlayers,
                Raffle.RaffleState.OPEN,
                timeHasPassed
            )
        );
        raffle.performUpkeep(""); // this will revert as expected since only two condition is passed (only timeHasPassed condition is met & RaffleState is OPEN).
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestID()
        public
        raffleEnterMod
    {
        // act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /*
        for (uint256 index = 0; index < entries.length; index++) {
            console.log("Index => ", index);
            console.log("Topics:");
            for (
                uint256 topicIndex = 0;
                topicIndex < entries[index].topics.length;
                topicIndex++
            ) {
                console.logBytes32(entries[index].topics[topicIndex]);
            }
            console.log("data:");
            console.logBytes(entries[index].data);
            console.log("address: ");
            console.logAddress(entries[index].emitter);
        }
        */
        // * There are 2 entries in the performUpkeep. 1st one is from vrfCoordinator-Contract, Second is from Raffle-Contract, Which is from RequestedRaffleWinner-Event, It has 2 topics, What we need is 2nd one which is the requestId
        bytes32 requestId = entries[1].topics[1];
        console.log("request Id: ", uint256(requestId));

        // assert
        Raffle.RaffleState rfState = raffle.getRaffleState();
        console.log("Raffle State: ", uint256(rfState));
        assert(requestId > 0);
        // assert(rfState == Raffle.RaffleState.CALCULATING);
        assert(uint256(rfState) == 1);
    }

    // #######################################################
    //                  testFulfillRandomWords
    // #######################################################

    //! My First FUZZ TEST
    function testFullfillRandomWordsCanOnlyBeCalledAfterPerformUpKeep(
        uint256 randomRequestId
    ) public raffleEnterMod skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFullfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnterMod
        skipFork
    {
        // Arrange
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        uint256 initialBalance = 10 ether;

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, initialBalance);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 balanceAfterEnteringRaffle = address(1).balance;

        // act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        console.log("request Id: ", uint256(requestId));

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState rfState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 price = entranceFee * (additionalEntrants + 1);

        // assert
        assertEq(uint256(rfState), 0);
        assertEq(winnerBalance, balanceAfterEnteringRaffle + price);
        assert(startingTimeStamp < endingTimeStamp);
    }
}
