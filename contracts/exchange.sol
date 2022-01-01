// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../interfaces/erc20_interface.sol';
import '../libraries/safe_math.sol';
import './token.sol';


contract TokenExchange {
    using SafeMath for uint;
    address public admin;

    address tokenAddr = 0xb2BC8341a009b6803978b32E361567A8daE429a2;  // token contract address.
    BrotherCoin private token = BrotherCoin(tokenAddr);    

    // Liquidity pool for the exchange
    uint public token_reserves = 0;
    uint public eth_reserves = 0;

    // Constant: x * y = k
    uint public k;

    uint public liquidity_amount = 0;
    mapping(address => uint) public liquidity_by_provider;
    address[] public providers;
    
    uint public bips = 10000;

    // liquidity rewards
    uint private swap_fee_numerator = 3;       // Set liquidity providers' returns.
    uint private swap_fee_denominator = 100;
    uint public pending_eth_reward = 0;
    uint public pending_token_reward = 0;

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

        // Keep track of the initial liquidity added so the initial provider
        //          can remove this liquidity
        liquidity_amount = msg.value;
        liquidity_by_provider[msg.sender] = msg.value;
        providers.push(msg.sender);
    }

    /* Be sure to use the SafeMath library for all operations! */
    
    // Function priceToken: Calculate the price of your token in ETH.
    // You can change the inputs, or the scope of your function, as needed.
    function priceToken() 
        public 
        view
        returns (uint)
    {
        /* HINTS:
            Calculate how much ETH is of equivalent worth based on the current exchange rate.
        */
        return eth_reserves.mul(bips).div(token_reserves);
    }

    // Function priceETH: Calculate the price of ETH for your token.
    // You can change the inputs, or the scope of your function, as needed.
    function priceETH()
        public
        view
        returns (uint)
    {
        /* HINTS:
            Calculate how much of your token is of equivalent worth based on the current exchange rate.
        */
        return token_reserves.mul(bips).div(eth_reserves);
    }


    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value)
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        /* HINTS:
            Calculate the liquidity to be added based on what was sent in and the prices.
            If the caller possesses insufficient tokens to equal the ETH sent, then transaction must fail.
            Update token_reserves, eth_reserves, and k.
            Emit AddLiquidity event.
        */

        if (max_exchange_rate > 0 && min_exchange_rate > 0) {
            require(priceToken().div(100) <= max_exchange_rate, "Max token slippage reached.");
            require(priceToken().div(100) >= min_exchange_rate, "Min token slippage reached.");
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
        if (liquidity_by_provider[msg.sender] == 0) {
            providers.push(msg.sender);
        }
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
        /* HINTS:
            Calculate the amount of your tokens that should be also removed.
            Transfer the ETH and Token to the provider.
            Update token_reserves, eth_reserves, and k.
            Emit RemoveLiquidity event.
        */

        if (max_exchange_rate > 0 && min_exchange_rate > 0) {
            require(priceToken().div(100) <= max_exchange_rate, "Max token slippage reached.");
            require(priceToken().div(100) >= min_exchange_rate, "Min token slippage reached.");
        }

        require(eth_reserves >= amountETH, "eth reserves must >= amount eth");
        
        uint remove_token_val = amountETH.mul(token_reserves).div(eth_reserves);
        uint tk_balance = token.balanceOf(address(this));

        // hack
        if (remove_token_val > tk_balance) {
            remove_token_val = tk_balance;
        }
        if (amountETH > address(this).balance) {
            amountETH = address(this).balance;
        }

        emit debugValue(remove_token_val, amountETH);

        // transfer from contract to caller(msg.sender)
        token.transfer(msg.sender, remove_token_val);
        payable(msg.sender).transfer(amountETH);

        // burn LP token
        // https://hackmd.io/@HaydenAdams/HJ9jLsfTz?type=view#Removing-Liquidity
        // ethWithdrawal = ethPool * (amountBurn / totalLiquidity)
        uint lp_token_burn = amountETH.mul(liquidity_amount).div(eth_reserves);
        liquidity_amount = liquidity_amount.sub(lp_token_burn);
        if (liquidity_amount > liquidity_by_provider[msg.sender]) {
            liquidity_by_provider[msg.sender] = 0;
        } else{
            liquidity_by_provider[msg.sender] = liquidity_by_provider[msg.sender].sub(liquidity_amount);
        }

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
        /* HINTS:
            Decide on the maximum allowable ETH that msg.sender can remove.
            Call removeLiquidity().
        */

        uint amount_eth = attempt_to_remove_all();
        removeLiquidity(amount_eth, 0, 0);

        // There is an edge case where balances are not wiped out completely
        // we reset pool to mitigate this case.
        // if (providers.length == 1) {
        //     eth_reserves = 0;
        //     token_reserves = 0;
        //     pending_eth_reward = 0;
        //     pending_token_reward = 0;
        // }
        remove_provider(0);
    }
    
    function remove_provider(uint index) private {
        if (index >= providers.length) return;

        for (uint i = index; i<providers.length-1; i++){
            providers[i] = providers[i+1];
        }
        delete providers[providers.length-1];
    }

    /***  Define helper functions for liquidity management here as needed: ***/
    function attempt_to_remove_all() public returns(uint) {
        uint amount_burn = liquidity_by_provider[msg.sender];
        uint amount_eth = eth_reserves.mul(amount_burn).div(liquidity_amount);

        uint own = address(this).balance;
        if (amount_eth > own) {
            // somehow contract own less eth, reset (hack)
            amount_eth = own;
        }

        emit debugValue(amount_eth, own);

        uint remove_token_val = amount_eth.mul(token_reserves).div(eth_reserves);
        uint tk_balance = token.balanceOf(address(this));

        emit debugValue(remove_token_val, tk_balance);

        // use token max instead of eth max!
        if (tk_balance < remove_token_val) {
            remove_token_val = tk_balance;
            amount_eth = remove_token_val.mul(bips).div(priceETH());
        }

        if (amount_eth > own) {
            amount_eth = own;
        }

        emit debugValue(remove_token_val, amount_eth);

        return amount_eth;
    }


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
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
            require(priceETH().div(100) <= max_exchange_rate, "Max slippage reached.");
        }

        require(amountTokens > 0);
        require(amountTokens <= token.balanceOf(msg.sender), "msg sender does not have enough amountTokens tp swap");

        // calculate fees
        uint token_swap_fee = amountTokens.mul(swap_fee_numerator).div(swap_fee_denominator);

        amountTokens = amountTokens.sub(token_swap_fee);
        
        // (eth - out) * (token + in) = k
        uint new_token_reserves = token_reserves.add(amountTokens);
        uint new_eth_reserves = k.div(new_token_reserves);
        require(new_eth_reserves > 0, "new eth reserves must > 0");
        uint eth_swapped = eth_reserves.sub(new_eth_reserves);
        
        require(eth_swapped > 0, "swapped eth must > 0");
        require(eth_reserves.sub(eth_swapped) != 0, "swap will exhaust eth pool");

        // hack
        if (eth_swapped > address(this).balance) {
            eth_swapped = address(this).balance;
        }
        
        token.transferFrom(msg.sender, address(this), amountTokens);
        payable(msg.sender).transfer(eth_swapped);

        // Update reserve pools
        token_reserves = new_token_reserves;
        eth_reserves = new_eth_reserves;

        distribute_token_fee(token_swap_fee);

        /***************************/
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

        /*
        Swapping fees are immediately deposited into liquidity reserves. 
        Since total reserves are increased without adding any additional share tokens, 
        this increases that value of all share tokens equally. 
        This functions as a payout to liquidity providers that can be collected by burning shares.

        Since fees are added to liquidity pools, the invariant increases at the end of every trade. 
        Within a single transaction, the invariant represents eth_pool * token_pool 
        at the end of the previous transaction.
        */

        if (max_exchange_rate > 0) {
            require(priceToken().div(100) <= max_exchange_rate, "Max slippage reached.");
        }

        // Calculate token swapped
        require(msg.value > 0);

        // calculate fees
        uint eth_fee = msg.value.mul(swap_fee_numerator).div(swap_fee_denominator);

        // reset eth_in = msg.value - fees
        uint eth_in = msg.value.sub(eth_fee);
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

        distribute_eth_fee(eth_fee);

        /**************************/
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

    function distribute_eth_fee(uint fee) public {
        uint total = 0;
        uint liquidity_fee_mint = fee.mul(liquidity_amount).div(eth_reserves);
        for (uint i = 0; i < providers.length; i++) {
            uint lp_token = liquidity_by_provider[providers[i]];
            if (lp_token == 0) {
                continue;
            }
            uint fee_lp_reward = liquidity_fee_mint.mul(lp_token).div(liquidity_amount);
            liquidity_by_provider[providers[i]] = lp_token.add(fee_lp_reward);

            emit debugValue(i, fee_lp_reward);
            total = total.add(fee_lp_reward);
        }

        liquidity_amount = liquidity_amount.add(liquidity_fee_mint);
        pending_eth_reward = pending_eth_reward.add(fee);

        reinvest_fee_to_pool();
    }

    function distribute_token_fee(uint fee) public {
        uint liquidity_fee_mint = fee.mul(liquidity_amount).div(token_reserves);
        for (uint i = 0; i < providers.length; i++) {
            uint lp_token = liquidity_by_provider[providers[i]];
            if (lp_token == 0) {
                continue;
            }
            uint fee_lp_reward = liquidity_fee_mint.mul(lp_token).div(liquidity_amount);
            emit debugValue(liquidity_fee_mint, fee_lp_reward);
            liquidity_by_provider[providers[i]] = lp_token.add(fee_lp_reward);
        }
        liquidity_amount = liquidity_amount.add(liquidity_fee_mint);
        pending_token_reward = pending_token_reward.add(fee);

        reinvest_fee_to_pool();
    }

    function reinvest_fee_to_pool() public {
        if (pending_eth_reward <= 0 || pending_token_reward <= 0) {
            return;
        }

        // find eth-token pair
        uint amount_eth = pending_eth_reward;
        uint amount_token = amount_eth.mul(bips).div(priceToken());
        if (amount_token > pending_token_reward) {
            // not enough token to pair with eth
            // re-calculate eth to match our token
            amount_token = pending_token_reward;
            amount_eth = amount_token.mul(bips).div(priceETH());
        }

        token_reserves = token_reserves.add(amount_token);
        eth_reserves = eth_reserves.add(amount_eth);
        k = token_reserves.mul(eth_reserves);
        if (amount_token >= pending_token_reward) {
            pending_token_reward = 0;
        } else {
            pending_token_reward = pending_token_reward.sub(amount_token);
        }

        if (amount_eth >= pending_eth_reward) {
            pending_eth_reward = 0;
        } else {
            pending_eth_reward = pending_eth_reward.sub(amount_eth);
        }
    }
}
