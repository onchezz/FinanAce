use starknet::ContractAddress;
use array::{ArrayTrait};

#[starknet::interface]
trait FinancerTrait<T> {
    fn set_parameters(ref self: T, token_address: starknet::ContractAddress, fee_percentage: u256, withdraw_time: u64);
    fn register(ref self: T, amount: u256);
    fn send(ref self: T, amount: u256, from: starknet::ContractAddress, to: starknet::ContractAddress);
    fn withdraw(ref self: T, amount: u256);
    fn view_total_balance(self: @T) -> u256;
    fn view_financer_balance(self: @T, address: starknet::ContractAddress) -> u256;
}

#[starknet::contract]
mod Financer {

    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use financer::interface::IERC20ABI;
    use financer::interface::IERC20ABIDispatcher;
    use financer::interface::IERC20ABIDispatcherTrait;

   
    #[event] 
    #[derive(Drop, starknet::Event)]
    enum Event {
        Sent: Sent,
    }

    #[derive(Drop, starknet::Event)]
    struct Sent {
        #[key]
        relay_to: starknet::ContractAddress,
        #[key]
        amount: u256
    }

    #[storage]
    struct Storage {
        //verified relays
        registed_financer: LegacyMap<ContractAddress, bool>,
        //finance bal
        financer_balances: LegacyMap<ContractAddress, u256>,
        //trusted admin address 
        owner_address: starknet::ContractAddress,
        //token: in our case ERC20
        token: IERC20ABIDispatcher,
        //total amount in vault 
        amount_in_vault: u256,
        //total fees collected over time 
        fees_collected: u256,
        // fee percentage is a constant, maybe should not be in storage??  
        fee_percentage: u256,
        //amount of time it takes to confirm exit of relay
        exit_timelock: u64
    }

    #[constructor]
    fn constructor(
        ref self: ContractState
    ) {
        let caller = get_caller_address();
        self.owner_address.write(caller);
    }

    #[external(v0)]
    impl finance of super::FinancerTrait<ContractState> {  

        fn view_total_balance(self: @ContractState) -> u256 {
            self.amount_in_vault.read()
        } 

        fn view_financer_balance(self: @ContractState, address: starknet::ContractAddress) -> u256 {
            //confirm to is a registered relay 
            assert(self.registed_financer.read(address) == true, 'to is not a relay');
            self.financer_balances.read(address)
        }       

        // ETH: 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
        // fee percentage: 0x2
        // withdraw_time: 24 hrs which is 86400s which is 0x15180 in hex
        fn set_parameters(
            ref self: ContractState, token_address: starknet::ContractAddress, fee_percentage: u256, withdraw_time: u64
        ) {
            let caller = get_caller_address();
            assert(caller == self.owner_address.read(), 'Not owner');
            self.owner_address.write(caller);
            self.token.write(IERC20ABIDispatcher {contract_address: token_address});
            self.fee_percentage.write(fee_percentage);
            self.exit_timelock.write(withdraw_time);
        }

        // // @dev How individual relays register to the vault by sending a certain amount of money
        fn register(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();

            let this_contract = get_contract_address();

            // TODO: assert token is equal to ETh address 
            // assert(self.token.read() != 0, 'token not initialized');

            self.token.read().transfer_from(
                caller, 
                this_contract, 
                amount);
            
            self.registed_financer.write(caller, true);   
            let current_amount = self.amount_in_vault.read();
            self.amount_in_vault.write(current_amount + amount);
            return ();   
        }
        
        // @dev The 'trusted' admin, as an intermediary, sends tokens to receiver relay. Balance of sender relay is deducted while receiver relay is added
        fn send(ref self: ContractState, amount: u256, from: starknet::ContractAddress, to: starknet::ContractAddress) {

            self.check_admin();
            
            let this_contract = get_contract_address();

            let caller = get_caller_address();

            
            // self.check_balance_helper(amount);           

            self.token.read().transfer_from(
                this_contract, 
                to, 
                amount
            );

            self.financer_balances.write(from, self.financer_balances.read(from) - amount);
            self.financer_balances.write(to, self.financer_balances.read(to) + amount); 

            self.emit(Event::Sent(Sent {
                relay_to: to,
                amount: amount,
            }));
        }
        
        // @dev A relay can withdraw their funds and stop being a relay. Their is a cool down period of time until funds actually exit the contract  
        fn withdraw (ref self: ContractState, amount: u256) {

            let this_contract = get_contract_address();
            let caller = get_caller_address();
            let withdraw_period: u64 = self.exit_timelock.read();

            self.check_balance_helper(amount);
            self.financer_balances.write(caller, self.financer_balances.read(caller) - amount);

            let current_amount = self.amount_in_vault.read();
            self.amount_in_vault.write(current_amount - amount);
            
            if (get_block_timestamp() > get_block_timestamp() + withdraw_period) {
                self.token.read().transfer_from(this_contract, caller, amount);
            } 
            return();
        }

    }

    //
    //internal
    //
    #[generate_trait]
    impl PrivateMethods of PrivateMethodsTrait {

        fn check_balance_helper(self: @ContractState, amount: u256) {
            let caller = get_caller_address();

            assert(self.registed_financer.read(caller) == true, 'not a inthe system');

            assert(self.financer_balances.read(caller) > amount, 'No liquidity');

            return();
        }

        fn check_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner_address.read(), 'Not the admin');
        }
    }
    

    impl IERC20ABIImpl of IERC20ABI<ContractState> {
        fn transfer_from(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256)
            {
                self.token.read().balance_of(sender) - amount;
                self.token.read().balance_of(recipient) + amount;
            }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 
            {
                self.token.read().balance_of(account)
            }

    }

}