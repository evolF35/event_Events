// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Claim is ERC20, Ownable {
    constructor(string memory name, string memory acronym) ERC20(name,acronym) {
    }
    function mint(uint256 amount) external onlyOwner {
        _mint(msg.sender,amount);
    }
    function burn(uint256 amount) public {
        _burn(msg.sender,amount);
    }
}

contract Pool {

    using SafeERC20 for Claim;

    uint256 startDate;
    uint256 settlementDate;
    uint256 diffBetwStartSettle;

    int256 price;
    address oracleAddress;

    uint256 decayFactor;

    // address decayAddress;
    // address capitalfactorAddress;
    // uint256 capitalFactor;

    uint256 minRatio;
    uint256 minRatioDate;

    bool condition;
    bool withdraw;

    uint256 numDepPos = 0;
    uint256 numDepNeg = 0;
    mapping (address => uint) PosAmtDeposited;
    mapping (address => uint) NegAmtDeposited;

    Claim public positiveSide;
    Claim public negativeSide;

    event ClaimsCreated(address POS, address NEG);

    AggregatorV3Interface public oracle;

    function getDepNumPOS() public view returns (uint256){
        return(numDepPos);
    }

    function getDepNumNEG() public view returns (uint256){
        return(numDepNeg);
    }

    function getCurrentRatio() public view returns (uint256){
        return(numDepPos/numDepNeg);
    }

    function getCondition() public view returns (bool){
        return(condition);
    }
    function withdrawOn() public view returns (bool){
        return(withdraw);
    }

    function pastSettlementDate() public view returns (bool){
        return(block.timestamp > settlementDate);
    }

    function getDiscountedValue() public view returns (uint256){
        uint256 temp = block.timestamp - startDate;
        uint256 dividedDecay = (decayFactor/100);
        uint256 end = ((temp*dividedDecay)/86400);
        uint256 tots = 1-end;
        return(tots);
    }

    constructor(
        address _oracle, int256 _price, 
        uint256 _settlementDate,uint256 _decay, 
        uint256 _minRatio, uint256 _minRatioDate,
        string memory name,string memory acronym) 
        {
        startDate = block.timestamp;
        settlementDate = _settlementDate;
        diffBetwStartSettle = settlementDate - startDate;

        price = _price;
        oracleAddress = _oracle;
        decayFactor = _decay;
        minRatio = _minRatio;
        minRatioDate = _minRatioDate;

        string memory over = "Over";
        string memory Over = string(bytes.concat(bytes(name), "-", bytes(over)));

        string memory under = "Under";
        string memory Under = string(bytes.concat(bytes(name), "-", bytes(under)));

        string memory Pacr = "POS";
        string memory PAC = string(bytes.concat(bytes(acronym), "-", bytes(Pacr)));

        string memory Nacr = "NEG";
        string memory NAC = string(bytes.concat(bytes(acronym), "-", bytes(Nacr)));

        positiveSide = new Claim(Over,PAC);
        negativeSide = new Claim(Under,NAC);

        emit ClaimsCreated(address(positiveSide), address(negativeSide));

        condition = false;

        oracle = AggregatorV3Interface(oracleAddress);
    }

    function depositToPOS() public payable {
        require(block.timestamp < settlementDate);
        require(msg.value > 0.001 ether, "mc");
        
        uint256 temp = block.timestamp - startDate;
        uint256 dividedDecay = (decayFactor/100);
        uint256 end = ((temp*dividedDecay)/86400);
        uint256 tots = 1-end;
        uint256 amt = tots*(msg.value);
        
        positiveSide.mint(amt);
        positiveSide.safeTransfer(msg.sender,amt);

        numDepPos = numDepPos + msg.value;
        PosAmtDeposited[msg.sender] = PosAmtDeposited[msg.sender] + msg.value;
    }

    function depositToNEG() public payable {
        require(block.timestamp < settlementDate);
        require(msg.value > 0.001 ether, "mc");
        
        negativeSide.mint(msg.value);
        negativeSide.safeTransfer(msg.sender,msg.value);

        uint256 temp = block.timestamp - startDate;
        uint256 dividedDecay = (decayFactor/100);
        uint256 end = ((temp*dividedDecay)/86400);
        uint256 tots = 1-end;
        uint256 amt = tots*(msg.value);
        
        negativeSide.mint(amt);
        negativeSide.safeTransfer(msg.sender,amt);

        numDepNeg = numDepNeg + msg.value;
        NegAmtDeposited[msg.sender] = NegAmtDeposited[msg.sender] + msg.value;
    }

    function settle() public {
        require(block.timestamp > settlementDate, "te");
        require(withdraw == false);

        (,int256 resultPrice,,,) = oracle.latestRoundData();

        if(resultPrice >= price){
            condition = true;
        }
    }

    function turnWithdrawOn() public {
        require(block.timestamp < minRatioDate, "pd");
        require(PosAmtDeposited[msg.sender] > 0 ||  NegAmtDeposited[msg.sender] > 0, "yn");
        require(minRatio < (numDepPos/numDepNeg), "CNS");
        if(minRatio < (numDepPos/numDepNeg)){
            withdraw = true;
        }
    }

    function redeemWithPOS() public { 
        require(withdraw == false,"rnf");
        require(block.timestamp > settlementDate, "te");
        require(condition == true,"cn");
        require(positiveSide.balanceOf(msg.sender) > 0, "yn");

        uint256 saved = ((positiveSide.balanceOf(msg.sender)*(address(this).balance))/positiveSide.totalSupply());
        
        positiveSide.safeTransferFrom(msg.sender,address(this),positiveSide.balanceOf(msg.sender));

        (payable(msg.sender)).transfer(saved);
    }

    function redeemWithNEG() public {
        require(withdraw == false,"rnf");
        require(block.timestamp > settlementDate, "te");
        require(condition == false,"cn");
        require(negativeSide.balanceOf(msg.sender) > 0, "yn");

        uint256 saved = ((negativeSide.balanceOf(msg.sender)*(address(this).balance))/negativeSide.totalSupply());
        
        negativeSide.safeTransferFrom(msg.sender,address(this),negativeSide.balanceOf(msg.sender));

        (payable(msg.sender)).transfer(saved);
    }

    function withdrawWithPOS() public {
        require(withdraw == true,"wf");
        require(positiveSide.balanceOf(msg.sender) > 0, "yn");

        positiveSide.safeTransferFrom(msg.sender,address(this),positiveSide.balanceOf(msg.sender));
        (payable(msg.sender)).transfer(PosAmtDeposited[msg.sender]);
        
        numDepPos = numDepPos - PosAmtDeposited[msg.sender];
        PosAmtDeposited[msg.sender] = 0;
    }

    function withdrawWithNEG() public {
        require(withdraw == true,"wf");
        require(negativeSide.balanceOf(msg.sender) > 0, "yn");

        negativeSide.safeTransferFrom(msg.sender,address(this),negativeSide.balanceOf(msg.sender));
        (payable(msg.sender)).transfer(NegAmtDeposited[msg.sender]);

        numDepNeg = numDepNeg - NegAmtDeposited[msg.sender];
        NegAmtDeposited[msg.sender] = 0;
    }
}

contract deploy {
    event PoolCreated(address _oracle, 
        int256 _price, uint256 _settlementDate,
        uint256 decay,uint256 minRatio,
        uint256 minRatioDate,string name,
        string acronym,address poolAddress);

    function createPool(address oracle, int256 price, 
        uint256 settlementDate,uint256 decay,
        uint256 minRatio,uint256 minRatioDate,
        string memory name,string memory acronym ) 
    
            public returns (address newPool)
            {
                newPool = address(new Pool(oracle,price,settlementDate,decay,minRatio,minRatioDate,name,acronym));
                emit PoolCreated(oracle,price,settlementDate,decay,minRatio,minRatioDate,name,acronym,newPool);
                return(newPool);
            }
}


