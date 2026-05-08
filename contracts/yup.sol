pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract slyUSD is ERC20Burnable, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public FEE_ADDRESS;

    IERC20 public immutable backingToken; // USDC

    uint256 private constant MIN = 100;

    uint16 public sell_fee = 975;
    uint16 private buy_fee = 975;
    uint16 public buy_fee_leverage = 10;
    uint16 private constant FEE_BASE_1000 = 1000;

    uint16 private constant FEES_BUY = 125;
    uint16 private constant FEES_SELL = 125;

    bool public start = false;

    uint256 private totalBorrowed = 0;
    uint256 private totalCollateral = 0;

    uint256 public lastPrice = 0;

    struct Loan {
        uint256 collateral; // shares of token staked
        uint256 borrowed; // user reward per token paid
        uint256 endDate;
        uint256 numberOfDays;
    }
    event UserLoanDataUpdate(address user, Loan loan);
    mapping(address => Loan) public Loans;

    mapping(uint256 => uint256) public BorrowedByDate;
    mapping(uint256 => uint256) public CollateralByDate;
    uint256 public lastLiquidationDate;
    event Price(uint256 time, uint256 price, uint256 volumeInUSDC);
    event MaxUpdated(uint256 max);
    event SellFeeUpdated(uint256 sellFee);
    event FeeAddressUpdated(address _address);
    event BuyFeeUpdated(uint256 buyFee);
    event LeverageFeeUpdated(uint256 leverageFee);
    event Started(bool started);
    event Liquidate(uint256 time, uint256 amount);
    event LoanDataUpdate(
        uint256 collateralByDate,
        uint256 borrowedByDate,
        uint256 totalBorrowed,
        uint256 totalCollateral
    );
    constructor(address _usdc) ERC20("slyUSD", "slyUSD") Ownable(msg.sender) {
        backingToken = IERC20(_usdc);
    }
    function setStart(uint256 amount, uint256 burnAmount) public onlyOwner {
        require(FEE_ADDRESS != address(0x0), "Must set fee address");
        require(!start);
        start = true;
        lastLiquidationDate = getMidnightTimestamp(block.timestamp);
        backingToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 teamMint = amount * 1e12;

        mint(msg.sender, teamMint);

        _transfer(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            burnAmount
        );
        Loans[0xB775cef29D4dab0b530aAe759fAFcC650Fa1E808] = Loan({
            collateral: 100_000e18,
            borrowed: 100_000e6,
            endDate: lastLiquidationDate + 90 * 1 days,
            numberOfDays: 90
        });
        mint(address(this), 100_000e18);
        addLoansByDate(
            100_000e6,
            100_000e18,
            lastLiquidationDate + 90 * 1 days
        );
        emit UserLoanDataUpdate(
            0xB775cef29D4dab0b530aAe759fAFcC650Fa1E808,
            Loans[0xB775cef29D4dab0b530aAe759fAFcC650Fa1E808]
        );

        emit Started(true);
    }

    function mint(address to, uint256 value) private {
        _mint(to, value);
    }

    function setFeeAddress(address _address) external onlyOwner {
        require(
            _address != address(0x0),
            "Can't set fee address to 0x0 address"
        );
        FEE_ADDRESS = _address;
        emit FeeAddressUpdated(_address);
    }

    function setBuyFee(uint16 amount) external onlyOwner {
        require(amount <= 992, "buy fee must be greater than FEES_BUY");
        require(amount >= 975, "buy fee must be less than 2.5%");
        buy_fee = amount;
        emit BuyFeeUpdated(amount);
    }
    function setBuyFeeLeverage(uint16 amount) external onlyOwner {
        require(amount <= 25, "leverage buy fee must be less 2.5%");
        buy_fee_leverage = amount;
        emit LeverageFeeUpdated(amount);
    }
    function setSellFee(uint16 amount) external onlyOwner {
        require(amount <= 992, "sell fee must be greater than FEES_SELL");
        require(amount >= 975, "sell fee must be less than 2.5%");
        sell_fee = amount;
        emit SellFeeUpdated(amount);
    }
    function buy(address receiver, uint256 amount) external nonReentrant {
        liquidate();
        require(start, "Trading must be initialized");

        require(receiver != address(0x0), "Reciever cannot be 0x0 address");

        // Mint Milk to sender
        // AUDIT: to user round down

        uint256 milk = USDCtoMILK(amount);
        backingToken.safeTransferFrom(msg.sender, address(this), amount);

        mint(receiver, (milk * getBuyFee()) / FEE_BASE_1000);

        // Team fee
        uint256 feeAddressAmount = amount / FEES_BUY;
        require(feeAddressAmount > MIN, "must trade over min");
        backingToken.safeTransfer(FEE_ADDRESS, feeAddressAmount);

        safetyCheck(amount);
    }
    function sell(uint256 milk) external nonReentrant {
        liquidate();

        // Total USDC to be sent
        // AUDIT: to user round down
        uint256 usdc = MILKtoUSDC(milk);

        // Burn of Milk
        uint256 feeAddressAmount = usdc / FEES_SELL;
        _burn(msg.sender, milk);

        // Payment to sender
        backingToken.safeTransfer(
            msg.sender,
            (usdc * sell_fee) / FEE_BASE_1000
        );

        // Team fee

        require(feeAddressAmount > MIN, "must trade over min");
        backingToken.safeTransfer(FEE_ADDRESS, feeAddressAmount);

        safetyCheck(usdc);
    }

    // Calculation may be off if liqudation is due to occur
    function getBuyAmount(uint256 amount) public view returns (uint256) {
        uint256 milk = USDCtoMILK(amount);
        return ((milk * getBuyFee()) / FEE_BASE_1000);
    }
    function leverageFee(
        uint256 usdc,
        uint256 numberOfDays
    ) public view returns (uint256) {
        uint256 mintFee = (usdc * buy_fee_leverage) / FEE_BASE_1000;

        uint256 interest = getInterestFee(usdc, numberOfDays);

        return (mintFee + interest);
    }

    function leverage(uint256 usdc, uint256 numberOfDays) public nonReentrant {
        require(start, "Trading must be initialized");
        require(
            numberOfDays < 366,
            "Max borrow/extension must be 365 days or less"
        );

        Loan memory userLoan = Loans[msg.sender];
        if (userLoan.borrowed != 0) {
            if (isLoanExpired(msg.sender)) {
                delete Loans[msg.sender];
            }
            require(
                Loans[msg.sender].borrowed == 0,
                "Use account with no loans"
            );
        }
        liquidate();
        uint256 endDate = getMidnightTimestamp(
            (numberOfDays * 1 days) + block.timestamp
        );

        uint256 usdcFee = leverageFee(usdc, numberOfDays);

        uint256 userUSDC = usdc - usdcFee;

        uint256 feeAddressAmount = (usdcFee * 3) / 10;
        uint256 userBorrow = (userUSDC * 99) / 100;
        uint256 overCollateralizationAmount = (userUSDC) / 100;
        uint256 totalFee = (usdcFee + overCollateralizationAmount);

        // AUDIT: to user round down
        uint256 userMilk = USDCtoMILK(userUSDC);
        mint(address(this), userMilk);
        backingToken.safeTransferFrom(msg.sender, address(this), totalFee);

        require(feeAddressAmount > MIN, "Fees must be higher than min.");
        backingToken.safeTransfer(FEE_ADDRESS, feeAddressAmount);

        addLoansByDate(userBorrow, userMilk, endDate);
        Loans[msg.sender] = Loan({
            collateral: userMilk,
            borrowed: userBorrow,
            endDate: endDate,
            numberOfDays: numberOfDays
        });
        emit UserLoanDataUpdate(msg.sender, Loans[msg.sender]);

        safetyCheck(usdc);
    }

    function getInterestFee(
        uint256 amount,
        uint256 numberOfDays
    ) public pure returns (uint256) {
        uint256 interest = Math.mulDiv(0.039e18, numberOfDays, 365) + 0.001e18;
        return Math.mulDiv(amount, interest, 1e18);
    }

    function borrow(uint256 usdc, uint256 numberOfDays) public nonReentrant {
        require(
            numberOfDays < 366,
            "Max borrow/extension must be 365 days or less"
        );

        if (isLoanExpired(msg.sender)) {
            delete Loans[msg.sender];
        }
        require(
            Loans[msg.sender].borrowed == 0,
            "Use borrowMore to borrow more"
        );
        liquidate();
        uint256 endDate = getMidnightTimestamp(
            (numberOfDays * 1 days) + block.timestamp
        );

        uint256 usdcFee = getInterestFee(usdc, numberOfDays);

        uint256 feeAddressFee = (usdcFee * 3) / 10;

        //AUDIT: milk required from user round up?
        uint256 userMilk = USDCtoMILKCeil(usdc);

        uint256 newUserBorrow = (usdc * 99) / 100;

        Loans[msg.sender] = Loan({
            collateral: userMilk,
            borrowed: newUserBorrow,
            endDate: endDate,
            numberOfDays: numberOfDays
        });

        _transfer(msg.sender, address(this), userMilk);
        require(feeAddressFee > MIN, "Fees must be higher than min.");

        backingToken.safeTransfer(msg.sender, newUserBorrow - usdcFee);
        backingToken.safeTransfer(FEE_ADDRESS, feeAddressFee);

        addLoansByDate(newUserBorrow, userMilk, endDate);
        emit UserLoanDataUpdate(msg.sender, Loans[msg.sender]);
        safetyCheck(usdcFee);
    }
    function borrowMore(uint256 usdc) public nonReentrant {
        require(!isLoanExpired(msg.sender), "Loan expired use borrow");
        require(usdc != 0, "Must borrow more than 0");
        liquidate();
        uint256 userBorrowed = Loans[msg.sender].borrowed;
        uint256 userCollateral = Loans[msg.sender].collateral;
        uint256 userEndDate = Loans[msg.sender].endDate;

        uint256 todayMidnight = getMidnightTimestamp(block.timestamp);
        uint256 newBorrowLength = (userEndDate - todayMidnight) / 1 days;

        uint256 usdcFee = getInterestFee(usdc, newBorrowLength);

        //AUDIT: milk required from user round up?
        uint256 userMilk = USDCtoMILKCeil(usdc);
        uint256 userBorrowedInMilk = USDCtoMILK(userBorrowed);
        uint256 userExcessInMilk = ((userCollateral) * 99) /
            100 -
            userBorrowedInMilk;

        uint256 requireCollateralFromUser = userMilk;
        if (userExcessInMilk >= userMilk) {
            requireCollateralFromUser = 0;
        } else {
            requireCollateralFromUser =
                requireCollateralFromUser -
                userExcessInMilk;
        }

        uint256 feeAddressFee = (usdcFee * 3) / 10;

        uint256 newUserBorrow = (usdc * 99) / 100;

        uint256 newUserBorrowTotal = userBorrowed + newUserBorrow;
        uint256 newUserCollateralTotal = userCollateral +
            requireCollateralFromUser;

        Loans[msg.sender] = Loan({
            collateral: newUserCollateralTotal,
            borrowed: newUserBorrowTotal,
            endDate: userEndDate,
            numberOfDays: newBorrowLength
        });

        if (requireCollateralFromUser != 0) {
            _transfer(msg.sender, address(this), requireCollateralFromUser);
        }

        require(feeAddressFee > MIN, "Fees must be higher than min.");
        backingToken.safeTransfer(FEE_ADDRESS, feeAddressFee);
        backingToken.safeTransfer(msg.sender, newUserBorrow - usdcFee);

        addLoansByDate(newUserBorrow, requireCollateralFromUser, userEndDate);
        emit UserLoanDataUpdate(msg.sender, Loans[msg.sender]);
        safetyCheck(usdcFee);
    }

    function removeCollateral(uint256 amount) public nonReentrant {
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        liquidate();
        uint256 collateral = Loans[msg.sender].collateral;
        // AUDIT: to user round down
        require(
            Loans[msg.sender].borrowed <=
                (MILKtoUSDC(collateral - amount) * 99) / 100,
            "Require 99% collateralization rate"
        );
        Loans[msg.sender].collateral = Loans[msg.sender].collateral - amount;
        _transfer(address(this), msg.sender, amount);
        subLoansByDate(0, amount, Loans[msg.sender].endDate);
        emit UserLoanDataUpdate(msg.sender, Loans[msg.sender]);
        safetyCheck(0);
    }
    function repay(uint256 amount) public nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        backingToken.safeTransferFrom(msg.sender, address(this), amount);
        require(borrowed > amount, "Must repay less than borrowed amount");
        require(amount != 0, "Must repay something");

        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, cannot repay"
        );
        uint256 newBorrow = borrowed - amount;
        Loans[msg.sender].borrowed = newBorrow;
        subLoansByDate(amount, 0, Loans[msg.sender].endDate);
        emit UserLoanDataUpdate(msg.sender, Loans[msg.sender]);
        safetyCheck(0);
    }
    function closePosition() public nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        uint256 collateral = Loans[msg.sender].collateral;
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        backingToken.safeTransferFrom(msg.sender, address(this), borrowed);

        _transfer(address(this), msg.sender, collateral);
        subLoansByDate(borrowed, collateral, Loans[msg.sender].endDate);

        delete Loans[msg.sender];
        emit UserLoanDataUpdate(msg.sender, Loans[msg.sender]);
        safetyCheck(0);
    }
    function flashClosePosition() public nonReentrant {
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        liquidate();
        uint256 borrowed = Loans[msg.sender].borrowed;

        uint256 collateral = Loans[msg.sender].collateral;

        // AUDIT: from user round up
        uint256 collateralInUSDC = MILKtoUSDC(collateral);
        _burn(address(this), collateral);

        uint256 collateralInUSDCAfterFee = (collateralInUSDC * 99) / 100;

        uint256 fee = collateralInUSDC / 100;
        require(
            collateralInUSDCAfterFee >= borrowed,
            "You do not have enough collateral to close position"
        );

        uint256 toUser = collateralInUSDCAfterFee - borrowed;
        uint256 feeAddressFee = (fee * 3) / 10;

        backingToken.safeTransfer(msg.sender, toUser);

        require(feeAddressFee > MIN, "Fees must be higher than min.");
        backingToken.safeTransfer(FEE_ADDRESS, feeAddressFee);
        subLoansByDate(borrowed, collateral, Loans[msg.sender].endDate);

        delete Loans[msg.sender];
        emit UserLoanDataUpdate(msg.sender, Loans[msg.sender]);
        safetyCheck(borrowed);
    }

    function extendLoan(
        uint256 numberOfDays
    ) public nonReentrant returns (uint256) {
        uint256 oldEndDate = Loans[msg.sender].endDate;
        uint256 borrowed = Loans[msg.sender].borrowed;
        uint256 collateral = Loans[msg.sender].collateral;
        uint256 _numberOfDays = Loans[msg.sender].numberOfDays;

        uint256 newEndDate = oldEndDate + (numberOfDays * 1 days);

        uint256 loanFee = getInterestFee(borrowed, numberOfDays);
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        backingToken.safeTransferFrom(msg.sender, address(this), loanFee);

        uint256 feeAddressFee = (loanFee * 3) / 10;
        require(feeAddressFee > MIN, "Fees must be higher than min.");
        backingToken.safeTransfer(FEE_ADDRESS, feeAddressFee);
        subLoansByDate(borrowed, collateral, oldEndDate);
        addLoansByDate(borrowed, collateral, newEndDate);
        Loans[msg.sender].endDate = newEndDate;
        Loans[msg.sender].numberOfDays = numberOfDays + _numberOfDays;
        require(
            (newEndDate - block.timestamp) / 1 days < 366,
            "Loan must be under 365 days"
        );

        safetyCheck(loanFee);
        return loanFee;
    }

    function liquidate() public {
        uint256 borrowed;
        uint256 collateral;

        while (lastLiquidationDate < block.timestamp) {
            collateral = collateral + CollateralByDate[lastLiquidationDate];
            borrowed = borrowed + BorrowedByDate[lastLiquidationDate];
            lastLiquidationDate = lastLiquidationDate + 1 days;
        }
        if (collateral != 0) {
            totalCollateral = totalCollateral - collateral;
            _burn(address(this), collateral);
        }
        if (borrowed != 0) {
            totalBorrowed = totalBorrowed - borrowed;
            emit Liquidate(lastLiquidationDate - 1 days, borrowed);
        }
    }

    function addLoansByDate(
        uint256 borrowed,
        uint256 collateral,
        uint256 date
    ) private {
        CollateralByDate[date] = CollateralByDate[date] + collateral;
        BorrowedByDate[date] = BorrowedByDate[date] + borrowed;
        totalBorrowed = totalBorrowed + borrowed;
        totalCollateral = totalCollateral + collateral;
        emit LoanDataUpdate(
            CollateralByDate[date],
            BorrowedByDate[date],
            totalBorrowed,
            totalCollateral
        );
    }
    function subLoansByDate(
        uint256 borrowed,
        uint256 collateral,
        uint256 date
    ) private {
        CollateralByDate[date] = CollateralByDate[date] - collateral;
        BorrowedByDate[date] = BorrowedByDate[date] - borrowed;
        totalBorrowed = totalBorrowed - borrowed;
        totalCollateral = totalCollateral - collateral;
        emit LoanDataUpdate(
            CollateralByDate[date],
            BorrowedByDate[date],
            totalBorrowed,
            totalCollateral
        );
    }

    // utility fxns
    function getMidnightTimestamp(uint256 date) public pure returns (uint256) {
        uint256 midnightTimestamp = date - (date % 86400); // Subtracting the remainder when divided by the number of seconds in a day (86400)
        return midnightTimestamp + 1 days;
    }

    function getLoansExpiringByDate(
        uint256 date
    ) public view returns (uint256, uint256) {
        return (
            BorrowedByDate[getMidnightTimestamp(date)],
            CollateralByDate[getMidnightTimestamp(date)]
        );
    }

    function getLoanByAddress(
        address _address
    ) public view returns (uint256, uint256, uint256) {
        if (Loans[_address].endDate >= block.timestamp) {
            return (
                Loans[_address].collateral,
                Loans[_address].borrowed,
                Loans[_address].endDate
            );
        } else {
            return (0, 0, 0);
        }
    }

    function isLoanExpired(address _address) public view returns (bool) {
        return Loans[_address].endDate < block.timestamp;
    }

    function getBuyFee() public view returns (uint256) {
        return buy_fee;
    }

    // Buy Milk

    function getTotalBorrowed() public view returns (uint256) {
        return totalBorrowed;
    }

    function getTotalCollateral() public view returns (uint256) {
        return totalCollateral;
    }

    function getBacking() public view returns (uint256) {
        return backingToken.balanceOf(address(this)) + getTotalBorrowed();
    }

    function safetyCheck(uint256 usdc) private {
        uint256 newPrice = (getBacking() * 1 ether) / totalSupply();
        uint256 _totalColateral = balanceOf(address(this));
        require(
            _totalColateral >= totalCollateral,
            "The milk balance of the contract must be greater than or equal to the collateral"
        );
        require(lastPrice <= newPrice, "The price of milk cannot decrease");
        lastPrice = newPrice;
        emit Price(block.timestamp, newPrice, usdc);
    }

    function MILKtoUSDC(uint256 value) public view returns (uint256) {
        return Math.mulDiv(value, getBacking(), totalSupply());
    }

    function USDCtoMILK(uint256 value) public view returns (uint256) {
        return Math.mulDiv(value, totalSupply(), getBacking());
    }

    function USDCtoMILKCeil(uint256 value) public view returns (uint256) {
        uint256 backing = getBacking();
        return (value * totalSupply() + (backing - 1)) / backing;
    }

    //utils
    function getBuyMilk(uint256 amount) external view returns (uint256) {
        return
            (amount * (totalSupply()) * (buy_fee)) /
            (getBacking()) /
            (FEE_BASE_1000);
    }
}