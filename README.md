# DSS Safebox

A safebox for digital assets.

## Usage

There are 3 "roles" in this contract:

1. `owner`: has full control of how much and when it can send assets to `recipient`.
2. `custodian`: cooperates whenever the `owner` wants to update the `recipient`.
3. `recipient`: receives assets from the safebox.

Role management and admin function are implemented using common MCD patterns.

## Note on Security

The change of the `recipient` address is a 2-step process and can be though of as a custom `2-out-of-N` multisig implementation, where both an `owner` and a `custodian` must collaborate.

However, a naive implementation could create room for a potential front-running attack:

1. The `owner` initiates the process to change the `recipient` and let the `custodian` know.
2. The `custodian` checks the pending address and creates a transaction to approve it.
3. The `owner` then front-runs the `custodian`'s transaction to change `recipient` to a different address.
4. Once the `custodian` transaction is included in a block, the `recipient` will be different from the agreed one.

To prevent such scenario, we use the common pattern of having both parties to provide the value of the changed parameter in the payload of both the transactions. If there is a mismatch, the second transaction will fail.
