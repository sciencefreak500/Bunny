// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface CVaultBSCFlipState {
    enum State {
        Idle, Farming
    }

    struct Account {
        uint nonce;
        State state;
    }

    struct Pool {
        address vault;
        address flip;

        mapping (address => Account) accounts;
    }
}