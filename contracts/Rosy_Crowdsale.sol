// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IROSYVesting {
    function createVestingSchedule(
        address _buyer,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriod,
        uint256 _amounttge,
        uint256 _amount
    ) external;

    function transferOwnership(address _newOwner) external;
}

contract ROSY_ICOT is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;
    ERC20 public USDTtoken; //address of usdt
    ERC20 public DAItoken; //address of dai
    ERC20 public BUSDtoken; //address of busd
    ERC20 public RosyWhaletoken; //address of the ROSY token
    IROSYVesting public ROSYtoken; //address of the ROSYvesting smart contract

    uint256 public earlybirdtokensforsale = 13_500_000 * 10 ** 18; //amount availabe for purchase in seed stage: 3%
    uint256 public seedtokensforsale = 54_000_000 * 10 ** 18; //amount availabe for purchase in seed stage: 12%
    uint256 public privatetokensforsale = 54_000_000 * 10 ** 18; //amount availabe for purchase in private stage: 12%

    bool public startLock = false; //locking the start function after execution

    uint256 startVTime; //relaese time of the tokens to the buyers (tge), init vesting start

    event StageChanged(uint _e);

    enum Stages {
        none, //initial stage before the presale starts
        earlybirdstage, //earlybird
        seedstage, //seed stage
        privatstage, //private stage
        icoEnd //ending stage after the presale
    }

    Stages public currentStage;

    /**
     * @dev initalizes the crowdsale contract
     * @param _tokenaddress address of the ROSY token
     * @param _vestingscaddress address of the vesting smart contract
     * @param _USDTtokenaddress address of usdt
     * @param _DAItokenaddress address of dai
     * @param _BUSDtokenaddress address of busd
     */
    constructor(
        address _tokenaddress,
        address _vestingscaddress,
        address _USDTtokenaddress,
        address _DAItokenaddress,
        address _BUSDtokenaddress
    ) {
        currentStage = Stages.none;
        RosyWhaletoken = ERC20(_tokenaddress);
        ROSYtoken = IROSYVesting(_vestingscaddress);
        USDTtoken = ERC20(_USDTtokenaddress);
        DAItoken = ERC20(_DAItokenaddress);
        BUSDtoken = ERC20(_BUSDtokenaddress);
    }

    /**
     * @dev initalize vesting function/
     * @notice call before the start of the presale
     * @param _starttime sets the release time in seconds of the purchased tokens (tge)
     * so e.g. 60 * 60 * 24 * 30 = 2592000 would set the tge to 30 days after calling the function
     */
    function startVesting(uint _starttime) external onlyOwner {
        require(startLock == false, "Function already executed");
        startLock = true;
        startVTime = block.timestamp + _starttime;
        startTeamVesting();
    }

    /**
     * @dev function to buy token with USDT
     * @notice first stablecoin needs to be approved (front-end)
     * @param _amount amount of ROSY tokens buyer wants to purchase
     * @param _id stablecoin used for purchase
     * id 1 = USDT
     * id 2 = DAI
     * id 3 = BUSD
     */
    function buyToken(uint256 _amount, uint _id) public {
        require(_amount > 0, "Amount can't be 0");
        ERC20 stableToken = getCoin(_id);
        uint256 approvedAmount = stableToken.allowance(
            msg.sender,
            address(this)
        );
        uint256 price = getPrice();
        uint256 totalPrice = (_amount * 10) / price;
        require(
            approvedAmount >= totalPrice,
            "Check the token allowance, not enough approved!"
        );
        stableToken.safeTransferFrom(msg.sender, address(this), totalPrice);
        transferVesting(msg.sender, _amount);
    }

    /**
     * @dev function to get the price denomintor for the current stage
     * e.g. seedstage price denominator = 500 => 1/500 = 0.02
     * @return price price denominator of current price
     */
    function getPrice() public view returns (uint256 price) {
        require(
                currentStage == Stages.earlybirdstage ||
                currentStage == Stages.seedstage ||
                currentStage == Stages.privatstage,
            "Sale not active"
        );
        if (currentStage == Stages.earlybirdstage) {
            return 1000; //0.01
        } else if (currentStage == Stages.seedstage) {
            return 500; //0.02
        } else if (currentStage == Stages.privatstage) {
            return 625; //0.025
        }
    }

    /**
     * @dev adding an outside investment
     * @param _address address of the outside buyer
     * @param _amount amount of tokens that the buyer bought !Don't forget to add the decimales 1 = 1000000000000000000 (18*0)
     */
    function addInvestment(address _address, uint _amount) external onlyOwner {
        require(_amount >= 1 * 10 ** 18, "Amount has to be at least 1"); //to make sure caller didn't forget to add the decimals
        transferVesting(_address, _amount);
    }

    /**
     * @dev Setting the presale stage
     * @param _value index of stage
     * 0 - none
     * 1 - seed
     * 2 - private
     * 3 - end
     */
    function setStage(uint _value) public onlyOwner {
        require(uint(Stages.icoEnd) >= _value, "Stage doesn't exist");
        currentStage = Stages(_value);
        emit StageChanged(_value);
    }

    /**
     * @dev function use to withdraw the stablecoins from the contract
     * @param amount amount of the stablecoin
     * @param id stabelcoin:
     * id 1 = USDT
     * id 2 = DAI
     * id 3 = BUSD
     */
    function withdraw(
        uint256 amount,
        uint id
    ) external onlyOwner returns (bool success) {
        ERC20 stableToken = getCoin(id);
        require(
            stableToken.balanceOf(address(this)) >= amount,
            "Not enough funds on the contract"
        );
        stableToken.safeTransfer(msg.sender, amount);
        return true;
    }

    /**
     * @dev Regain the ownership of the vesting contract (this is just a precautious measurement to make sure the vesting function could be executed if e.g. a buyer is not able to get the tokens etc.)
     * @param _address address of the new owner
     */
    function changeOwnerOfVestingContract(address _address) external onlyOwner {
        require(_address != address(0), "Owner can't be the 0 address");
        ENCDtoken.transferOwnership(_address);
    }

    /**
     * @dev create vesting schedule after a purchase
     * @param _buyer address of buyer
     * @param _amount purchased amount
     */
    function transferVesting(address _buyer, uint _amount) internal {
        if (currentStage == Stages.earlybirdstage) {
            require(
                seedtokensforsale > 0,
                "All tokens in this stage sold, wait for the next stage"
            );
            require(
                seedtokensforsale >= _amount,
                "Not enough tokens left for purchase in this stage"
            );
            seedtokensforsale -= _amount;
            ROSYtoken.createVestingSchedule(
                _buyer,
                startVTime,
                60 * 60 * 24 * 30 * 1,
                60 * 60 * 24 * 30 * 10,
                60 * 60 * 24,
                (_amount * 500) / 10000, //5.00%
                _amount
            );
        } else if (currentStage == Stages.seedstage) {
            require(
                seedtokensforsale > 0,
                "All tokens in this stage sold, wait for the next stage"
            );
            require(
                seedtokensforsale >= _amount,
                "Not enough tokens left for purchase in this stage"
            );
            seedtokensforsale -= _amount;
            ROSYtoken.createVestingSchedule(
                _buyer,
                startVTime,
                60 * 60 * 24 * 30 * 1,
                60 * 60 * 24 * 30 * 12,
                60 * 60 * 24,
                (_amount * 200) / 10000, //2.00%
                _amount
            );
        } else if (currentStage == Stages.privatstage) {
            require(
                privatetokensforsale > 0,
                "All tokens in this stage sold, wait for the next stage"
            );
            require(
                privatetokensforsale >= _amount,
                "Not enough tokens left for purchase in this stage"
            );
            privatetokensforsale -= _amount;
            ROSYtoken.createVestingSchedule(
                _buyer,
                startVTime,
                60 * 60 * 24 * 30 * 1,
                60 * 60 * 24 * 30 * 11,
                60 * 60 * 24,
                (_amount * 200) / 10000, //2.00%
                _amount
            );
        }
    }

    /**
     * @dev creation of the team vesting schedule
     * called after vesting start
     */
    function startTeamVesting() internal {
        //Team
        ROSYtoken.createVestingSchedule(
            0x362dF3CB4a57e5c745Fd08A3b818EDd0E39929AE,
            startVTime,
            60 * 60 * 24 * 30 * 12,
            60 * 60 * 24 * 30 * 12,
            60 * 60 * 24,
            0,
            36000000 * 10 ** 18
        );
        //Advisors
        ROSYtoken.createVestingSchedule(
            0xA8089eA86bc6073FD94e554935c2fd90FF30F18f,
            startVTime,
            60 * 60 * 24 * 30 * 8,
            60 * 60 * 24 * 30 * 10,
            60 * 60 * 24,
            0,
            22500000 * 10 ** 18
        );
        //Marketing
        ROSYtoken.createVestingSchedule(
            0x1d505b7926DcD5a4A0807419bF750a6A9b871178,
            startVTime,
            60 * 60 * 24 * 30 * 1,
            60 * 60 * 24 * 30 * 24,
            60 * 60 * 24,
            0,
            45000000 * 10 ** 18
        );
        //Operational
        ROSYtoken.createVestingSchedule(
            0xE433DE6a6a019Db7d6473213Bb6EEcDdaeB123aa,
            startVTime,
            60 * 60 * 24 * 30 * 1,
            60 * 60 * 24 * 30 * 24,
            60 * 60 * 24,
            0,
            45000000 * 10 ** 18
        );
        //Treasury
        ROSYtoken.createVestingSchedule(
            0xcc4df77869b7F64346A524a114515E5BfC56eA36,
            startVTime,
            60 * 60 * 24 * 30 * 1,
            60 * 60 * 24 * 30 * 24,
            60 * 60 * 24,
            0,
            45000000 * 10 ** 18
        );
        //Rewards
        ROSYtoken.createVestingSchedule(
            0xFc034D957265c41554AEF915ea8B98277D6dA840,
            startVTime,
            60 * 60 * 24 * 30 * 1,
            60 * 60 * 24 * 30 * 12,
            60 * 60 * 24,
            0,
            67500000 * 10 ** 18
        );
    }

    /**
     * @dev get the stablecoin
     * @param _id id of stablecoin
     * @return _token returns stablecoin
     */
    function getCoin(uint _id) internal view returns (ERC20 _token) {
        require(_id <= 3 && 0 < _id, "invalid token id");
        if (_id == 1) {
            return USDTtoken;
        }
        if (_id == 2) {
            return DAItoken;
        }
        if (_id == 3) {
            return BUSDtoken;
        }
    }
}
