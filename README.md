# DSS Safebox

A safebox for digital assets.

- [Usage](#usage)
  - [Set up](#set-up)
  - [Deposit assets](#deposit-assets)
  - [Withdraw assets](#withdraw-assets)
  - [Change the `recipient` address](#change-the-recipient-address)

## Usage

There are 3 "roles" in this contract:

1. `owner`: has full control of how much and when it can send assets to `recipient`.
2. `custodian`: cooperates whenever the `owner` wants to update the `recipient`.
3. `recipient`: receives assets from the safebox.

`owner` and `custodian` are immutable. If they need to be replaced, a new contract needs to be deployed with the updated addresses.

### Set up

To create a `Safebox`, the deployer needs to provide the addresses of one `owner`, one `custodian` and the `recipient`.

### Deposit assets

There are 2 possible ways of making a deposit into the `Safebox`:

1. Use the `Safebox` address as the `to` address of a ERC-20 compatible `transfer` transaction.
2. Call the `deposit`<sup>[1]</sup> method from the `Safebox` contract:
   ```solidity
   safebox.deposit(<TOKEN_ADDRESS>, <TOKEN_AMOUNT>)
   ```

---

<sup>[1]</sup> Notice that this method requires an ERC-20 compatible `transferFrom` implementation with the right `allowance` given to the `Safebox` contract.

### Withdraw assets

An `owner` can withdraw assets to the `recipient` address at any time:

```solidity
safebox.withdraw(<TOKEN_ADDRESS>, <TOKEN_AMOUNT>)
```

### Change the `recipient` address

The change of the `recipient` address is a 2-step process and can be thought of as a custom `2-out-of-N` multisig implementation, where both an `owner` and a `custodian` must collaborate.

The `owner` starts the flow by calling:

```solidity
safebox.file("recipient", <NEW_RECIPIENT>)
```

The `custodian` confirms the change by calling:

```solidity
safebox.approveRecipientChange(<NEW_RECIPIENT>)
```

Notice that `<NEW_RECIPIENT>` must be the same, otherwise the transaction will revert<sup>[2]</sup>.

---

<sup>[2]</sup> A naive implementation of the change `recipient` flow could create room for a potential front-running attack:

1. The `owner` initiates the process to change the `recipient` and let the `custodian` know.
2. The `custodian` checks the pending address and creates a transaction to approve it.
3. The `owner` then front-runs the `custodian`'s transaction to change `recipient` to a different address.
4. Once the `custodian` transaction is included in a block, the `recipient` will be different from the agreed one.

To prevent such scenario, we use the common pattern of having both parties to provide the value of the changed parameter in the payload of both the transactions. If there is a mismatch, the second transaction will fail.
