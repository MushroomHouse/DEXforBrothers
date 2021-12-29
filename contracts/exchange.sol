// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../interfaces/erc20_interface.sol';
import '../libraries/safe_math.sol';
import './token.sol';


contract TokenExchange {
    using SafeMath for uint;
    address public admin;

    address tokenAddr = 0xd27C7e83174D8f78283149573F603372F51A774f;  // token contract address.
    BrotherCoin private token = BrotherCoin(tokenAddr);    

    // Liquidity pool for the exchange
    uint public token_reserves = 0;
    uint public eth_reserves = 0;

    // Constant: x * y = k
    uint public k;

    uint public liquidity_amount = 0;
    mapping(address => uint) public liquidity_by_provider;
    
    // liquidity rewards
    uint private swap_fee_numerator = 0;       // TODO Part 5: Set liquidity providers' returns.
    uint private swap_fee_denominator = 100;
    
    event AddLiquidity(address from, uint amount);
    event RemoveLiquidity(address to, uint amountETH, uint amountToken);
    event Received(address from, uint amountETH);
    event debugValue(uint amount1, uint amount2);

    constructor() 
    {
        admin = msg.sender;
    }
    
    modifier AdminOnly {
        require(msg.sender == admin, "Only admin can use this function!");
        _;
    }

    // Used for receiving ETH
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
    fallback() external payable{}

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        AdminOnly
    {
        // require pool does not yet exist
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need ETH to create pool.");
        require (amountTokens > 0, "Need tokens to create pool.");

        // approve token sending
        require (token.balanceOf(msg.sender) >= amountTokens);
        token.approve(address(this), amountTokens);

        token.transferFrom(msg.sender, address(this), amountTokens);

        eth_reserves = msg.value;
        token_reserves = amountTokens;
        k = eth_reserves.mul(token_reserves);

        // TODO: Keep track of the initial liquidity added so the initial provider
        //          can remove this liquidity
        liquidity_amount = msg.value;
        liquidity_by_provider[msg.sender] = msg.value;
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    /* Be sure to use the SafeMath library for all operations! */
    
    // Function priceToken: Calculate the price of your token in ETH.
    // You can change the inputs, or the scope of your function, as needed.
    function priceToken() 
        public 
        view
        returns (uint)
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Calculate how much ETH is of equivalent worth based on the current exchange rate.
        */
        return eth_reserves.mul(100).div(token_reserves);
    }

    // Function priceETH: Calculate the price of ETH for your token.
    // You can change the inputs, or the scope of your function, as needed.
    function priceETH()
        public
        view
        returns (uint)
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Calculate how much of your token is of equivalent worth based on the current exchange rate.
        */
        return token_reserves.mul(100).div(eth_reserves);
    }


    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value)
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Calculate the liquidity to be added based on what was sent in and the prices.
            If the caller possesses insufficient tokens to equal the ETH sent, then transaction must fail.
            Update token_reserves, eth_reserves, and k.
            Emit AddLiquidity event.
        */
        if (max_exchange_rate > 0 && min_exchange_rate > 0) {
            require(priceToken() <= max_exchange_rate, "Max token slippage reached.");
            require(priceToken() >= min_exchange_rate, "Min token slippage reached.");
        }
        
        uint eth_val = msg.value;
        require(msg.value > 0, "msg value must > 0");

        // Calculate required token, and verify provider has enough token to supply
        uint token_amount = eth_val.mul(token_reserves).div(eth_reserves).add(1);
        uint tk_balance = token.balanceOf(msg.sender);
        require(tk_balance >= token_amount, "tk_balance must >= token_amount");

        token.transferFrom(msg.sender, address(this), token_amount);

        // mint LP token
        // Use the formula from uniswap v1
        uint liquidity_mint = eth_val.mul(liquidity_amount).div(eth_reserves);
        liquidity_amount = liquidity_amount.add(liquidity_mint);
        liquidity_by_provider[msg.sender] = liquidity_by_provider[msg.sender].add(liquidity_mint);

        // Update records
        eth_reserves = eth_reserves.add(msg.value);
        token_reserves = token_reserves.add(token_amount);
        k = eth_reserves.mul(token_reserves);        
        
        emit AddLiquidity(msg.sender, eth_val);
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Calculate the amount of your tokens that should be also removed.
            Transfer the ETH and Token to the provider.
            Update token_reserves, eth_reserves, and k.
            Emit RemoveLiquidity event.
        */
        if (max_exchange_rate > 0 && min_exchange_rate > 0) {
            require(priceToken() <= max_exchange_rate, "Max token slippage reached.");
            require(priceToken() >= min_exchange_rate, "Min token slippage reached.");
        }

        require(eth_reserves >= amountETH, "eth reserves must >= amount eth");

        uint remove_token_val = amountETH.mul(token_reserves).div(eth_reserves);
        uint tk_balance = token.balanceOf(address(this));
        require(tk_balance >= remove_token_val, "balance less than withdrawal");

        emit debugValue(remove_token_val, amountETH);

        // transfer from contract to caller(msg.sender)
        token.transfer(msg.sender, remove_token_val);
        payable(msg.sender).transfer(amountETH);

        // burn LP token
        // https://hackmd.io/@HaydenAdams/HJ9jLsfTz?type=view#Removing-Liquidity
        // ethWithdrawal = ethPool * (amountBurn / totalLiquidity)
        uint lp_token_burn = amountETH.mul(liquidity_amount).div(eth_reserves);
        liquidity_amount = liquidity_amount.sub(lp_token_burn);
        liquidity_by_provider[msg.sender] = liquidity_by_provider[msg.sender].sub(liquidity_amount);

        // Update records
        eth_reserves = eth_reserves.sub(amountETH);
        token_reserves = token_reserves.sub(remove_token_val);
        k = eth_reserves.mul(token_reserves);        
        
        emit RemoveLiquidity(msg.sender, amountETH, remove_token_val);
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity()
        external
        payable
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Decide on the maximum allowable ETH that msg.sender can remove.
            Call removeLiquidity().
        */

        uint amount_burn = liquidity_by_provider[msg.sender];
        uint amount_eth = eth_reserves.mul(amount_burn).div(liquidity_amount);
        removeLiquidity(amount_eth, 0, 0);
    }

    /***  Define helper functions for liquidity management here as needed: ***/



    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Calculate amount of ETH should be swapped based on exchange rate.
            Transfer the ETH to the provider.
            If the caller possesses insufficient tokens, transaction must fail.
            If performing the swap would exhaus total ETH supply, transaction must fail.
            Update token_reserves and eth_reserves.

            Part 4: 
                Expand the function to take in addition parameters as needed.
                If current exchange_rate > slippage limit, abort the swap.
            
            Part 5:
                Only exchange amountTokens * (1 - liquidity_percent), 
                    where % is sent to liquidity providers.
                Keep track of the liquidity fees to be added.
        */

        if (max_exchange_rate > 0) {
            require(priceETH() <= max_exchange_rate, "Max slippage reached.");
        }

        require(amountTokens > 0);
        // (eth - out) * (token + in) = k
        uint new_token_reserves = token_reserves.add(amountTokens);
        uint new_eth_reserves = k.div(new_token_reserves);
        require(new_eth_reserves > 0, "new eth reserves must > 0");
        uint eth_swapped = eth_reserves.sub(new_eth_reserves);
        
        require(eth_swapped > 0, "swapped eth must > 0");
        require(eth_reserves.sub(eth_swapped) != 0, "swap will exhaust eth pool");

        token.transferFrom(msg.sender, address(this), amountTokens);
        payable(msg.sender).transfer(eth_swapped);

        // Update reserve pools
        token_reserves = new_token_reserves;
        eth_reserves = new_eth_reserves;

        /***************************/
        // DO NOT MODIFY BELOW THIS LINE
        /* Check for x * y == k, assuming x and y are rounded to the nearest integer. */
        // Check for Math.abs(token_reserves * eth_reserves - k) < (token_reserves + eth_reserves + 1));
        //   to account for the small decimal errors during uint division rounding.
        uint check = token_reserves.mul(eth_reserves);
        if (check >= k) {
            check = check.sub(k);
        }
        else {
            check = k.sub(check);
        }
        assert(check < (token_reserves.add(eth_reserves).add(1)));
    }



    // Function swapETHForTokens: Swaps ETH for your tokens.
    // ETH is sent to contract as msg.value.
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Calculate amount of your tokens should be swapped based on exchange rate.
            Transfer the amount of your tokens to the provider.
            If performing the swap would exhaus total token supply, transaction must fail.
            Update token_reserves and eth_reserves.

            Part 4: 
                Expand the function to take in addition parameters as needed.
                If current exchange_rate > slippage limit, abort the swap. 
            
            Part 5: 
                Only exchange amountTokens * (1 - %liquidity), 
                    where % is sent to liquidity providers.
                Keep track of the liquidity fees to be added.
        */

        if (max_exchange_rate > 0) {
            require(priceToken() <= max_exchange_rate, "Max slippage reached.");
        }

        // Calculate token swapped
        require(msg.value > 0);

        uint eth_in = msg.value;
        // (eth + in) * (token - out) = k
        uint new_eth_reserves = eth_reserves.add(eth_in);

        uint new_token_reserves = k.div(new_eth_reserves);
        require(new_token_reserves > 0, "new token reserves must > 0");
        uint token_out = token_reserves.sub(new_token_reserves);
        
        require(token_out > 0, "swapped eth must > 0");

        emit debugValue(token_reserves, token_out);
        require(token_reserves != token_out, "swap will exhaust token pool");

        // send token from this contract to the caller(sender)
        token.transfer(msg.sender, token_out);

        // Update reserve pools
        token_reserves = new_token_reserves;
        eth_reserves = new_eth_reserves;

        /**************************/
        // DO NOT MODIFY BELOW THIS LINE
        /* Check for x * y == k, assuming x and y are rounded to the nearest integer. */
        // Check for Math.abs(token_reserves * eth_reserves - k) < (token_reserves + eth_reserves + 1));
        //   to account for the small decimal errors during uint division rounding.
        uint check = token_reserves.mul(eth_reserves);
        if (check >= k) {
            check = check.sub(k);
        }
        else {
            check = k.sub(check);
        }
        assert(check < (token_reserves.add(eth_reserves).add(1)));
    }

    /***  Define helper functions for swaps here as needed: ***/

}

