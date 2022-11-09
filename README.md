# DSS Safebox

A safebox for digital assets.

- [Overview](#overview)
- [Deployment](#deployment)
- [Usage](#usage)
  - [Deposit assets](#deposit-assets)
  - [Withdraw assets](#withdraw-assets)
  - [Change the `recipient` address](#change-the-recipient-address)

## Overview

There are 3 "roles" in this contract:

1. `owner`: has full control of how much and when it can send assets to `recipient`.
2. `custodian`: approves changes in the `recipient` address made by an `owner`.
3. `recipient`: receives assets from the safebox.

`owner` and `custodian` are immutable. If they need to be replaced, a new contract needs to be deployed with the updated addresses.

## Deployment

To create a `Safebox`, the deployer needs to provide the following parameters:

1. `vat`: The address of the MCD Vat module;
2. `token`: The address of the ERC-20 token that can be held in the safebox;
3. `owner`: The address of the owner of the contract (in general, this should be the main MakerDAO Governance contract `MCD_PAUSE_PROXY`);
4. `custodian`: The address of a custodian of the contract.
5. `recipient`: The destination address for tokens withdrawn from the safebox.

Deployed addresses:

- Mainnet: `TBD`
- Goerli: `TBD`

## Usage

### Deposit assets

There are 2 possible ways of making a deposit into the `Safebox`:

1. Use the `Safebox` address as the `to` address of an ERC-20 compatible `transfer` transaction.
2. Call the `deposit`<sup>[1]</sup> method from the `Safebox` contract:
   ```solidity
   safebox.deposit(<TOKEN_AMOUNT>)
   ```

---

<sup>[1]</sup> Notice that this method requires an ERC-20 compatible `transferFrom` implementation with the right `allowance` given to the `Safebox` contract.

### Withdraw assets

An `owner` can withdraw assets to the `recipient` address at any time:

```solidity
safebox.withdraw(<TOKEN_AMOUNT>)
```

### Change the `recipient` address

The change of the `recipient` address is a 2-step process and can be thought of as a custom `2-out-of-2` multisig implementation, where both an `owner` and a `custodian` must collaborate.

An `owner` starts the flow by calling:

```solidity
safebox.file("recipient", <NEW_RECIPIENT>)
```

A `custodian` confirms the change by calling:

```solidity
safebox.approveRecipientChange(<NEW_RECIPIENT>)
```

Notice that `<NEW_RECIPIENT>` must be the same, otherwise the transaction will revert<sup>[2]</sup>.

### Add/remove an owner

An `owner` can add or remove other owners using the following functions:

```solidity
// Add an owner
safebox.rely(<NEW_OWNER>);

// Remove an owner
safebox.deny(<FORMER_OWNER>);
```

⚠️ Notice that there are no safeguards against one removing themselves as the owner.

### Add/remove a custodian

A `custodian` can add or remove other custodians using the following functions:

```solidity
// Add a custodian
safebox.addCustodian(<NEW_CUSTODIAN>);

// Remove a custodian
safebox.removeCustodian(<FORMER_CUSTODIAN>);
```

⚠️ Notice that there are no safeguards against one removing themselves as the custodian.

---

<sup>[2]</sup> A naive implementation of the change `recipient` flow could create room for a potential front-running attack:

1. An `owner` initiates the process to change the `recipient` and let a `custodian` know.
2. A `custodian` checks the pending address and creates a transaction to approve it.
3. An `owner` then front-runs a `custodian`'s transaction to change `recipient` to a different address.
4. Once a `custodian` transaction is included in a block, the `recipient` will be different from the agreed one.

To prevent such scenario, we use the common pattern of having both parties to provide the value of the changed parameter in the payload of both the transactions. If there is a mismatch, the second transaction will fail.
