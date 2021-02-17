// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "./BankConfig.sol";


interface InterestModel {
    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);
}

contract TripleSlopeModel {
    using SafeMath for uint256;

    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 floating) external pure returns (uint256) {
        uint256 total = debt.add(floating);
        if (total == 0) return 0;

        uint256 utilization = debt.mul(10000).div(total);
        if (utilization < 5000) {
            // Less than 50% utilization - 10% APY
            return uint256(10e16) / 365 days;
        } else if (utilization < 9500) {
            // Between 50% and 95% - 10%-25% APY
            return (10e16 + utilization.sub(5000).mul(15e16).div(10000)) / 365 days;
        } else if (utilization < 10000) {
            // Between 95% and 100% - 25%-100% APY
            return (25e16 + utilization.sub(7500).mul(75e16).div(10000)) / 365 days;
        } else {
            // Not possible, but just in case - 100% APY
            return uint256(100e16) / 365 days;
        }
    }
}


contract ConfigurableInterestBankConfig is BankConfig, Ownable {
    /// The portion of interests allocated to the reserve pool.
    uint256 public override getReservePoolBps;

    /// Interest rate model
    InterestModel public interestModel;

    constructor(
        uint256 _reservePoolBps,
        InterestModel _interestModel
    ) public {
        setParams(_reservePoolBps, _interestModel);
    }

    /// @dev Set all the basic parameters. Must only be called by the owner.
    /// @param _reservePoolBps The new interests allocated to the reserve pool value.
    /// @param _interestModel The new interest rate model contract.
    function setParams(
        uint256 _reservePoolBps,
        InterestModel _interestModel
    ) public onlyOwner {
        getReservePoolBps = _reservePoolBps;
        interestModel = _interestModel;
    }

    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 floating) external view override returns (uint256) {
        return interestModel.getInterestRate(debt, floating);
    }
}