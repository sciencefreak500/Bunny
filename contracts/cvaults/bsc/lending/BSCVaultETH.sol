// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "../../../interfaces/IPancakePair.sol";
import "../../../interfaces/IPancakeRouter02.sol";

import "../../../library/PausableUpgradeable.sol";
import "../../interface/ILender.sol";
import "../../../library/Whitelist.sol";

contract BSCVaultETH is PausableUpgradeable, Whitelist {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant ETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    uint private constant MAX = 10000;
    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);

    uint public PERFORMANCE_FEE;
    ILender private _lender;

    address public keeper;

    uint private _treasuryFund;
    uint private _treasuryDebt;

    receive() external payable {}

    modifier onlyKeeper {
        require(msg.sender == keeper || msg.sender == owner(), "BSCVaultETH: not keeper");
        _;
    }

    // INITIALIZER

    function initialize() external initializer {
        __PausableUpgradeable_init();
        __Whitelist_init();

        PERFORMANCE_FEE = 1000;
        IBEP20(ETH).safeApprove(address(ROUTER), uint(-1));
    }

    // VIEWS

    function balance() external view returns(uint) {
        return IBEP20(ETH).balanceOf(address(this));
    }

    function lender() external view returns(address) {
        return address(_lender);
    }

    function treasuryFund() external view returns(uint) {
        return _treasuryFund;
    }

    function treasuryDebt() external view returns(uint) {
        return _treasuryDebt;
    }

    // RESTRICTED - onlyOwner

    function setPerformanceFee(uint newPerformanceFee) external onlyOwner {
        require(newPerformanceFee <= 5000, "BSCVaultETH: fee too much");
        PERFORMANCE_FEE = newPerformanceFee;
    }

    function setLender(address newLender) external onlyOwner {
        require(address(_lender) == address(0), "BSCVaultETH: setLender only once");
        _lender = ILender(newLender);

        IBEP20(ETH).safeApprove(newLender, uint(-1));
    }

    function setKeeper(address newKeeper) external onlyOwner {
        keeper = newKeeper;
    }

    function recoverToken(address _token, uint amount) external onlyOwner {
        require(_token != ETH, 'BSCVaultETH: cannot recover eth token');
        if (_token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IBEP20(_token).safeTransfer(owner(), amount);
        }
    }

    // RESTRICTED - Keeper
    function repayTreasuryDebt() external onlyKeeper returns(uint ethAmount) {
        address[] memory path = new address[](2);
        path[0] = ETH;
        path[1] = WBNB;

        uint debt = _lender.accruedDebtValOf(address(this), address(this));
        ethAmount = ROUTER.getAmountsIn(debt, path)[0];
        require(ethAmount <= IBEP20(ETH).balanceOf(address(this)), "BSCVaultETH: insufficient eth");

        if (_treasuryDebt >= ethAmount) {
            _treasuryFund = _treasuryFund.add(_treasuryDebt.sub(ethAmount));
            _treasuryDebt = 0;
            _repayTreasuryDebt(debt, ethAmount);
        } else if (_treasuryDebt.add(_treasuryFund) >= ethAmount) {
            _treasuryFund = _treasuryFund.sub(ethAmount.sub(_treasuryDebt));
            _treasuryDebt = 0;
            _repayTreasuryDebt(debt, ethAmount);
        } else {
            revert("BSCVaultETH: not enough eth balance");
        }
    }

    // panama bridge
    function transferTreasuryFund(address to, uint ethAmount) external onlyKeeper {
        IBEP20(ETH).safeTransfer(to, ethAmount);
    }

    // RESTRICTED - Cross farming contract only

    function repayOrHandOverDebt(address lp, address account, uint debt) external onlyWhitelisted returns(uint ethAmount)  {
        if (debt == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = ETH;
        path[1] = WBNB;

        ethAmount = ROUTER.getAmountsIn(debt, path)[0];
        uint ethBalance = IBEP20(ETH).balanceOf(address(this));
        if (ethAmount <= ethBalance) {
            // repay
            uint[] memory amounts = ROUTER.swapTokensForExactETH(debt, ethAmount, path, address(this), block.timestamp);
            _lender.repay{ value: amounts[1] }(lp, account);
        } else {
            if (ethBalance > 0) {
                uint[] memory amounts = ROUTER.swapExactTokensForETH(ethBalance, 0, path, address(this), block.timestamp);
                _lender.repay{ value: amounts[1] }(lp, account);
            }

            _treasuryDebt = _treasuryDebt.add(ethAmount.sub(ethBalance));
            // insufficient ETH !!!!
            // handover BNB debt
            _lender.handOverDebtToTreasury(lp, account);
        }
    }

    function depositTreasuryFund(uint ethAmount) external {
        IBEP20(ETH).transferFrom(msg.sender, address(this), ethAmount);
        _treasuryFund = _treasuryFund.add(ethAmount);
    }

    function transferProfit() external payable returns(uint ethAmount) {
        if (msg.value == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = ETH;

        uint[] memory amounts = ROUTER.swapExactETHForTokens{ value : msg.value }(0, path, address(this), block.timestamp);
        uint fee = amounts[1].mul(PERFORMANCE_FEE).div(MAX);

        _treasuryFund = _treasuryFund.add(fee);
        ethAmount = amounts[1].sub(fee);
    }

    // Private functions

    function _repayTreasuryDebt(uint debt, uint maxETHAmount) private {
        address[] memory path = new address[](2);
        path[0] = ETH;
        path[1] = WBNB;

        uint[] memory amounts = ROUTER.swapTokensForExactETH(debt, maxETHAmount, path, address(this), block.timestamp);
        _lender.repayTreasuryDebt{ value: amounts[1] }();
    }
}