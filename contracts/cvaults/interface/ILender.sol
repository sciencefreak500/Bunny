// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ILender {
    function debtValOf(address pool, address user) external view returns(uint);
    function debtShareOf(address pool, address user) external view returns(uint);
    function debtShareToVal(uint debtShare) external view returns (uint debtVal);
    function getUtilizationInfo() external view returns(uint totalBNB, uint debt);

    function accruedDebtValOf(address pool, address user) external returns(uint);
    function borrow(address pool, address borrower, uint debtVal) external returns(uint debt);
    function repay(address pool, address borrower) external payable returns(uint debtShares);

    // ETH Vault
    function handOverDebtToTreasury(address pool, address borrower) external returns(uint debtShares);
    function repayTreasuryDebt() external payable returns(uint debtShares);
}