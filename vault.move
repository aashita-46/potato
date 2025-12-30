module vault::aptos_vault {

    use std::signer;
    use std::error;
    use std::event;
    use std::option;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;

    const E_NOT_ADMIN: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_NOT_ALLOCATED: u64 = 3;

    struct TokensDepositedEvent has drop, store {
        amount: u64,
    }

    struct TokensWithdrawnEvent has drop, store {
        amount: u64,
    }

    struct TokensAllocatedEvent has drop, store {
        recipient: address,
        amount: u64,
    }

    struct TokensClaimedEvent has drop, store {
        recipient: address,
        amount: u64,
    }

    struct AdminTransferredEvent has drop, store {
        old_admin: address,
        new_admin: address,
    }

    struct Vault has key {
        admin: address,
        vault_address: address,
        total_balance: u64,
        allocated_balance: u64,
        allocations: table::Table<address, u64>,
        tokens_deposited_events: event::EventHandle<TokensDepositedEvent>,
        tokens_withdrawn_events: event::EventHandle<TokensWithdrawnEvent>,
        tokens_allocated_events: event::EventHandle<TokensAllocatedEvent>,
        tokens_claimed_events: event::EventHandle<TokensClaimedEvent>,
        admin_transferred_events: event::EventHandle<AdminTransferredEvent>,
    }

    /// Initialize vault under the admin account
    public entry fun init_module(admin: &signer) {
        let admin_address = signer::address_of(admin);

        move_to(admin, Vault {
            admin: admin_address,
            vault_address: admin_address,
            total_balance: 0,
            allocated_balance: 0,
            allocations: table::new<address, u64>(),
            tokens_deposited_events: event::new_event_handle<TokensDepositedEvent>(admin),
            tokens_withdrawn_events: event::new_event_handle<TokensWithdrawnEvent>(admin),
            tokens_allocated_events: event::new_event_handle<TokensAllocatedEvent>(admin),
            tokens_claimed_events: event::new_event_handle<TokensClaimedEvent>(admin),
            admin_transferred_events: event::new_event_handle<AdminTransferredEvent>(admin),
        });
    }

    /// Deposit tokens into vault
    public entry fun deposit_tokens(
        admin: &signer,
        vault_address: address,
        amount: u64
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);

        coin::transfer<AptosCoin>(admin, vault.vault_address, amount);
        vault.total_balance = vault.total_balance + amount;

        event::emit_event(
            &mut vault.tokens_deposited_events,
            TokensDepositedEvent { amount }
        );
    }

    /// Allocate tokens to recipient
    public entry fun allocate_tokens(
        admin: &signer,
        vault_address: address,
        recipient: address,
        amount: u64
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);
        assert!(
            vault.total_balance - vault.allocated_balance >= amount,
            E_INSUFFICIENT_BALANCE
        );

        let current = table::borrow_mut_with_default(
            &mut vault.allocations,
            recipient,
            0
        );

        *current = *current + amount;
        vault.allocated_balance = vault.allocated_balance + amount;

        event::emit_event(
            &mut vault.tokens_allocated_events,
            TokensAllocatedEvent { recipient, amount }
        );
    }

    /// Claim allocated tokens
    public entry fun claim_tokens(
        user: &signer,
        vault_address: address
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        let user_address = signer::address_of(user);

        let allocation = table::remove(&mut vault.allocations, user_address);
        assert!(allocation > 0, E_NOT_ALLOCATED);

        vault.allocated_balance = vault.allocated_balance - allocation;
        vault.total_balance = vault.total_balance - allocation;

        coin::transfer<AptosCoin>(vault_address, user_address, allocation);

        event::emit_event(
            &mut vault.tokens_claimed_events,
            TokensClaimedEvent { recipient: user_address, amount: allocation }
        );
    }

    /// Withdraw unallocated tokens
    public entry fun withdraw_tokens(
        admin: &signer,
        vault_address: address,
        amount: u64
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);
        assert!(
            vault.total_balance - vault.allocated_balance >= amount,
            E_INSUFFICIENT_BALANCE
        );

        vault.total_balance = vault.total_balance - amount;
        coin::transfer<AptosCoin>(vault_address, signer::address_of(admin), amount);

        event::emit_event(
            &mut vault.tokens_withdrawn_events,
            TokensWithdrawnEvent { amount }
        );
    }

    /// View allocated balance
    public fun get_allocation(
        vault_address: address,
        user: address
    ): u64 acquires Vault {
        let vault = borrow_global<Vault>(vault_address);
        *table::borrow_with_default(&vault.allocations, user, 0)
    }

    /// View vault balances
    public fun get_balances(vault_address: address): (u64, u64) acquires Vault {
        let vault = borrow_global<Vault>(vault_address);
        (vault.total_balance, vault.allocated_balance)
    }

    /// BONUS: Transfer vault ownership
    public entry fun transfer_admin(
        admin: &signer,
        vault_address: address,
        new_admin: address
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        let old_admin = vault.admin;

        assert!(old_admin == signer::address_of(admin), E_NOT_ADMIN);
        vault.admin = new_admin;

        event::emit_event(
            &mut vault.admin_transferred_events,
            AdminTransferredEvent {
                old_admin,
                new_admin,
            }
        );
    }
}
