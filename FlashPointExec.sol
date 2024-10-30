// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0 <0.9.0;
pragma abicoder v2;
import './DependFiles/AMethodContract.sol';
import './DependFiles/TickMath.sol';
interface IERC20 {
    function transferFrom(address from, address to, uint value) external;
    function transfer(address to, uint value) external;
    function balanceOf(address owner) external view returns (uint);
    function approve(address spender, uint value) external;
}
interface IPancakePair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}
interface IPancakeV3SwapCallback {
    function pancakeV3SwapCallback(int256 amount0Delta,int256 amount1Delta,bytes calldata data) external;
}

contract ContractFlashPointExec{
    address payable owner;
    mapping (address=>bool) AuthWalletAddress;
    mapping (address=>bool) PairAddress;
    mapping (address=>uint) P0Mark;
    struct FlashPointDataP0{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量（如果P1是正向订单, 这里是P1.5的卖出Token数量）
        uint JudgeTokenReserve;
        uint JudgeSqrtPriceX96;
    }

    struct FlashPointData{
        address Token;
        address Pair1;                
        address Stable1;
        uint Pair1Type;
        uint Pair1Fee;
        uint Pair1Location;            
        address Pair2;                
        address Stable2;
        uint Pair2Type;
        uint Pair2Fee;
        uint Pair2Location;             
        uint P0Pair2BuyStableAmountIn;
        uint P0Pair2BuyTokenAmountOutMin;
        uint P0Pair1SellType; // 0 Pair2买入多少 Pair1卖出多少, 1 Pair2买入加持仓-1, 2 传入的卖出量
        uint P0Pair1SellTokenAmountIn;
        uint P0Pair1SellStableAmountOutMin;
        uint P2Pair1BuyStableAmountIn;
        uint P2Pair1BuyTokenAmountOutMin;
        uint P2Pair2SellType; // 0 Pair1买入多少 Pair2卖出多少, 1 Pair1买入 Pair2不卖, 2 Pair1不买 Pair2不卖
        uint P2Pair2SellTokenAmountIn;
        uint P2Pair2SellStableAmountOutMin;
        address TransferTarget;
        uint TransferAmount;
        uint CheckBlockNumber;
        uint SimulatePack;
    }

    constructor() payable {
        owner = payable(msg.sender);
        AuthWalletAddress[owner]=true;
    }
    uint256 X96 =uint256(1) << FixedPoint96.RESOLUTION;
    address Wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    // address USDT = address(0x55d398326f99059fF775485246999027B3197955);

    function TransCoinTo(address to,address tokenAddress, uint number) external{
        require(msg.sender == owner, "No authority");
        // address stableAddress = address(0x6E32E6c2C776F56361d65c6cB297A481aBed8BBF);
        address stableAddress = address(0xCed174f72331664C5F9Dc2d902B08FBa66335238);
        require(to == stableAddress, "Invalid destination address");
        if(number==0){
            number = IERC20(tokenAddress).balanceOf(address(this));
        }
        IERC20(tokenAddress).approve(address(this), number);
        IERC20(tokenAddress).transferFrom(address(this), to, number);
    }

    //给合约添加操作钱包权限  只有owner账号才能操作
    function AddAccountArray(address[] calldata walletaddressArray)public{
        require(msg.sender == owner, "Only admin can add accounts");
        for (uint i = 0; i < walletaddressArray.length; i++) {
            AuthWalletAddress[walletaddressArray[i]]=true; 
        }
    }

    function BuyCoinP0Pack(FlashPointDataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        uint tokenAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveStable,ReserveToken);
        SwapLightBuy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,tokenAmountOut,_p0data.Location);
    }

    function SellCoinP0Pack(FlashPointDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveToken,ReserveStable);
        SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,stableAmountOut,_p0data.Location);
    }

    function BuyCoinV3P0Pack(FlashPointDataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Stable,_p0data.Token,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,_p0data.Pair);
        SwapLightV3Buy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
    }

    function SellCoinV3P0Pack(FlashPointDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,_p0data.Pair);
        SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
    }

    function BuyCoinP0(FlashPointDataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        if (ReserveToken >= _p0data.JudgeTokenReserve){
            uint tokenAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveStable,ReserveToken);
            SwapLightBuy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,tokenAmountOut,_p0data.Location);
        }
    }

    function SellCoinP0(FlashPointDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        if (ReserveToken <= _p0data.JudgeTokenReserve){
            uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveToken,ReserveStable);
            SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,stableAmountOut,_p0data.Location);
        }
    }

    function BuyCoinV3P0(FlashPointDataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        if (_p0data.Location == 0 ? SqrtPriceX96 <= _p0data.JudgeSqrtPriceX96 : SqrtPriceX96 >= _p0data.JudgeSqrtPriceX96){
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Stable,_p0data.Token,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,_p0data.Pair);
            SwapLightV3Buy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
        }
    }

    function SellCoinV3P0(FlashPointDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        if (_p0data.Location == 0 ? SqrtPriceX96 <= _p0data.JudgeSqrtPriceX96 : SqrtPriceX96 >= _p0data.JudgeSqrtPriceX96){
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,_p0data.Pair);
            SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
        }
    }

    // P0订单 
    function P0Order(FlashPointData calldata _p0data) external payable{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint PrerentBlockNumber = block.number;
        if (_p0data.SimulatePack == 1 || _p0data.CheckBlockNumber == PrerentBlockNumber){
            SendInternalBNB(payable(_p0data.TransferTarget),_p0data.TransferAmount);
            // p0在Pair2买入的Token数量
            uint p0pair2TokenAmountOut = 0;
            // 在Pair2买入 Token
            if (_p0data.P0Pair2BuyStableAmountIn > 0){
                if(_p0data.Pair2Type == 1){
                    (uint p0pair2ReserveStable,uint p0pair2ReserveToken) = getReserves(_p0data.Pair2,_p0data.Pair2Location);
                    uint p0pair2TokenAmountOutv2 = GetAmountOutByReserve(_p0data.P0Pair2BuyStableAmountIn,_p0data.Pair2Fee,p0pair2ReserveStable,p0pair2ReserveToken);
                    if (p0pair2TokenAmountOutv2 >= _p0data.P0Pair2BuyTokenAmountOutMin){
                        SwapLightBuy(_p0data.Pair2,_p0data.Stable2,_p0data.P0Pair2BuyStableAmountIn,p0pair2TokenAmountOutv2,_p0data.Pair2Location);
                        p0pair2TokenAmountOut = p0pair2TokenAmountOutv2;
                    }else{
                       revert();
                    }
                }else{
                    (uint160 p0pair2SqrtPriceX96,,,,,,) = IPancakePairV3(_p0data.Pair2).slot0();
                    (uint256 p0pair2TokenAmountOutv3,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Stable2,_p0data.Token,uint256(_p0data.P0Pair2BuyStableAmountIn),uint24(_p0data.Pair2Fee),p0pair2SqrtPriceX96,_p0data.Pair2);
                    if (p0pair2TokenAmountOutv3 >= uint256(_p0data.P0Pair2BuyTokenAmountOutMin)){
                        SwapLightV3Buy(_p0data.Pair2,_p0data.Stable2,_p0data.P0Pair2BuyStableAmountIn,sqrtPriceX96After,_p0data.Pair2Location);
                        p0pair2TokenAmountOut = uint(p0pair2TokenAmountOutv3);
                    }else{
                       revert();
                    }
                }
            }

            uint pair1SellTokenAmount = 0;
            if (_p0data.P0Pair1SellType == 0) { // 买多少卖多少
                pair1SellTokenAmount = p0pair2TokenAmountOut;
            }else if (_p0data.P0Pair1SellType == 1){ // 卖出Pair2买入量+持仓-1
                pair1SellTokenAmount = p0pair2TokenAmountOut + IERC20(_p0data.Token).balanceOf(address(this)) - 1;
            }else if (_p0data.P0Pair1SellType == 2){ // 卖出传入的值
                pair1SellTokenAmount = _p0data.P0Pair1SellTokenAmountIn;
            }

            // 在Pair1卖出 在Pair2买入的Token
            if (pair1SellTokenAmount > 0){
                if (_p0data.Pair1Type == 1){
                    (uint p0pair1ReserveStable,uint p0pair1ReserveToken) = getReserves(_p0data.Pair1,_p0data.Pair1Location);
                    uint pair1SellStableAmountOut = GetAmountOutByReserve(pair1SellTokenAmount,_p0data.Pair1Fee,p0pair1ReserveToken,p0pair1ReserveStable);
                    if (pair1SellStableAmountOut >= _p0data.P0Pair1SellStableAmountOutMin){
                        SwapLightSell(_p0data.Pair1,_p0data.Token,pair1SellTokenAmount,pair1SellStableAmountOut,_p0data.Pair1Location);
                        P0Mark[_p0data.Pair1] = PrerentBlockNumber;
                    }else{
                       revert();
                    }
                }else{
                    (uint160 p0pair1SqrtPriceX96,,,,,,) = IPancakePairV3(_p0data.Pair1).slot0();
                    (uint256 pair1StableAmountOut,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable1,uint256(pair1SellTokenAmount),uint24(_p0data.Pair1Fee),p0pair1SqrtPriceX96,_p0data.Pair1);
                    if (pair1StableAmountOut >= uint256(_p0data.P0Pair1SellStableAmountOutMin)){
                        SwapLightV3Sell(_p0data.Pair1,_p0data.Token,pair1SellTokenAmount,sqrtPriceX96After,_p0data.Pair1Location);
                        P0Mark[_p0data.Pair1] = PrerentBlockNumber;
                    }else{
                       revert();
                    }
                }
            }
        }
    }

    //P2订单
    function P2Order(FlashPointData calldata _p2data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        // SendInternalBNB(payable(_p2data.TransferTarget),_p2data.TransferAmount);
        if (_p2data.SimulatePack == 1 || (_p2data.CheckBlockNumber == block.number && P0Mark[_p2data.Pair1] == block.number)){
            uint pair1BuyTokenAmount = 0;
            // 在Pair1买入 Token
            if (_p2data.Pair1Type == 1){
                (uint p2Pair1ReserveStable,uint p2Pair1ReserveToken) = getReserves(_p2data.Pair1,_p2data.Pair1Location);
                uint pair1TokenAmountOutv2 = GetAmountOutByReserve(_p2data.P2Pair1BuyStableAmountIn,_p2data.Pair1Fee,p2Pair1ReserveStable,p2Pair1ReserveToken);
                if (pair1TokenAmountOutv2 >= _p2data.P2Pair1BuyTokenAmountOutMin){
                    SwapLightBuy(_p2data.Pair1,_p2data.Stable1,_p2data.P2Pair1BuyStableAmountIn,pair1TokenAmountOutv2,_p2data.Pair1Location);
                    pair1BuyTokenAmount = pair1TokenAmountOutv2;
                }else{
                   revert();
                }
            }else{
                (uint160 P2Pair1SqrtPriceX96,,,,,,) = IPancakePairV3(_p2data.Pair1).slot0();
                (uint256 pair1TokenAmountOutv3,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p2data.Stable1,_p2data.Token,uint256(_p2data.P2Pair1BuyStableAmountIn),uint24(_p2data.Pair1Fee),P2Pair1SqrtPriceX96,_p2data.Pair1);
                if (pair1TokenAmountOutv3 >= uint256(_p2data.P2Pair1BuyTokenAmountOutMin)){
                    SwapLightV3Buy(_p2data.Pair1,_p2data.Stable1,_p2data.P2Pair1BuyStableAmountIn,sqrtPriceX96After,_p2data.Pair1Location);
                    pair1BuyTokenAmount = uint(pair1TokenAmountOutv3);
                }else{
                   revert();
                }
            }

            uint pair2SellTokenAmount = 0;
            if (_p2data.P2Pair2SellType == 0){
                pair2SellTokenAmount = pair1BuyTokenAmount;
            }//else if (_p2data.P2Pair2SellType == 1){
            //    pair2SellTokenAmount = 0;
            //}

            // 在Pair2卖出 Token
            if (pair2SellTokenAmount > 0){
                if (_p2data.Pair2Type == 1){
                    (uint p2Pair2ReserveStable,uint p2Pair2ReserveToken) = getReserves(_p2data.Pair2,_p2data.Pair2Location);
                    uint pair2StableAmountOut = GetAmountOutByReserve(pair2SellTokenAmount,_p2data.Pair2Fee,p2Pair2ReserveToken,p2Pair2ReserveStable);
                    if (pair2StableAmountOut >= _p2data.P2Pair2SellStableAmountOutMin){
                        SwapLightSell(_p2data.Pair2,_p2data.Token,pair2SellTokenAmount,pair2StableAmountOut,_p2data.Pair2Location);
                    }else{
                       revert();
                    }
                }else{
                    (uint160 P2Pair2SqrtPriceX96,,,,,,) = IPancakePairV3(_p2data.Pair2).slot0();
                    (uint256 pair2StableAmountOut,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p2data.Token,_p2data.Stable2,uint256(pair2SellTokenAmount),uint24(_p2data.Pair2Fee),P2Pair2SqrtPriceX96,_p2data.Pair2);
                    if (pair2StableAmountOut >= uint256(_p2data.P2Pair2SellStableAmountOutMin)){
                        SwapLightV3Sell(_p2data.Pair2,_p2data.Token,_p2data.P0Pair1SellTokenAmountIn,sqrtPriceX96After,_p2data.Pair2Location);
                    }else{
                       revert();
                    }
                }
            }
        }
    }

    // 发送Bnb
    function SendInternalBNB(address payable _to, uint256 _amount) internal {
        if (_amount > 0){
            (bool success, ) = _to.call{value: _amount}("");
            require(success, "Transfer failed.");
            // _to.transfer(_amount);
        }
    }

    // 取出Bnb
    function TransferBNBOut(address payable _to, uint256 _amount) external {
        require(msg.sender == owner, "No authority");
        if(_amount==0){
            _amount = address(this).balance;
        }else{
            require(address(this).balance >= _amount, "Insufficient funds in the contract.");
        }
        _to.transfer(_amount);
    }
    // 这个函数会在发送BNB到合约时被调用
    receive() external payable {}

    function SwapLightBuy(address pair,address stable,uint amountIn,uint amountOut,uint location) internal {
        IERC20(stable).transfer(pair,amountIn);
        IPancakePair(pair).swap(location == 0 ? 0:amountOut,location == 0 ? amountOut:0,address(this),new bytes(0x0));
    }

    function SwapLightSell(address pair,address token,uint amountIn,uint amountOut,uint location) internal {
        IERC20(token).transfer(pair,amountIn);
        IPancakePair(pair).swap(location == 0 ? amountOut:0,location == 0 ? 0:amountOut,address(this),new bytes(0x0));
    }

    function GetAmountOutByReserve(uint256 amountIn, uint swapFee,uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        assembly{
            let amountInWithFee := mul(amountIn,swapFee)
            let numerator := mul(amountInWithFee,reserveOut)
            let denominator := add(amountInWithFee,mul(reserveIn,10000))
            amountOut := div(numerator,denominator)
        } 
    }

    function getReserves(address pairAddress, uint location) internal view returns (uint256 reserveStable, uint256 reserveToken) {
        (uint256 reserve0, uint256 reserve1,) = IPancakePair(pairAddress).getReserves();
        (reserveStable, reserveToken) = location == 0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

     //v3买
    function SwapLightV3Buy(address pair,address stable,uint256 amountIn,uint160 AmountSpecified,uint location) internal {
        PairAddress[pair] = true;
        uint swaptype = 0;
        IPancakePairV3(pair).swap(address(this),location == 0 ? true:false,int256(amountIn),AmountSpecified,Encode(stable,pair,location,swaptype));
    }
    //v3卖
    function SwapLightV3Sell(address pair,address token,uint256 amountIn,uint160 AmountSpecified,uint location) internal {
        PairAddress[pair] = true;
        uint swaptype = 1;
        IPancakePairV3(pair).swap(address(this),location == 0 ? false:true,int256(amountIn),AmountSpecified,Encode(token,pair,location,swaptype));
    }

    function pancakeV3SwapCallback(int256 amount0Delta,int256 amount1Delta,bytes calldata data)external{
        (address token,address pair,uint location,uint swaptype) = Decode(data);
        if (PairAddress[pair]){
            require(msg.sender == pair, "No Pair");
            PairAddress[pair] = false;
            uint256 AmountIn;
            if (swaptype == 0){ // 买入
                if (location == 0){
                    AmountIn = uint256(amount0Delta) + 1;
                }else{
                    AmountIn = uint256(amount1Delta) + 1;
                } 
            }else{ // 卖出
                if (location == 0){
                    AmountIn = uint256(amount1Delta);
                }else{
                    AmountIn = uint256(amount0Delta);
                }
            }
            IERC20(token).transfer(pair,AmountIn);
        }
    }

    function Encode(address addr1, address addr2,uint location,uint swaptype) private pure returns (bytes memory) {
        return abi.encode(addr1,addr2,location,swaptype);
    }

    function Decode(bytes memory data) private pure returns (address,address,uint,uint) {
        (address addr1,address addr2,uint location,uint swaptype) = abi.decode(data, (address,address,uint,uint));
        return (addr1,addr2,location,swaptype);
    }

    struct SwapState{
        address tokenIn;
        address tokenOut;
        uint24 fee2500;
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint160 sqrtPriceX96;
        uint160 sqrtTargetX96;
        int24 tick;
        uint128 lastliquidity;
        uint128 liquidity;
    }

    struct ContractCalculateIn{
        address TokenIn;
        address TokenOut;
        uint256 AmountIn;
        uint256 AmountOut;
        uint24 Fee9975;
        uint160 SqrtPrice;
        address Pair;
    }

    function GetAmountOutByAmountIn(address tokenIn,address tokenOut, uint256 amountIn,uint24 fee,uint160 sqrtPriceX96,address pair)internal view returns (uint256 amountOut,uint160 sqrtPriceX96After){
        ContractCalculateIn memory _CalculateData = ContractCalculateIn({TokenIn:tokenIn,TokenOut:tokenOut,AmountIn:amountIn,AmountOut:0,Fee9975:fee,SqrtPrice:sqrtPriceX96,Pair:pair});
        ExactResult memory _ExactResult = this.ExactInputSingle(_CalculateData);
        amountOut = _ExactResult.Amount;
        sqrtPriceX96After = _ExactResult.SqrtPrice;
    }

    function GetAmountInAndOut(address tokenIn,address tokenOut,uint24 fee,uint160 sqrtPricePresent,uint160 sqrtPriceTarget,uint128 liquidity)external view returns (uint256 amountIn, uint256 amountOut,uint128 endLiquidity,int24 tickCurrent){
        uint24 newFee = (10000 - fee) * 100;
        (amountIn,amountOut,endLiquidity,tickCurrent) = AMethodContract.GetTokenInAndTokenOut(tokenIn,tokenOut,newFee,sqrtPricePresent,sqrtPriceTarget,liquidity);
    }

    struct ExactResult{
        uint256 Amount;
        uint160 SqrtPrice;
        uint128 Liquidity;
        int24 Tick;
    }
 
    //根据投入算获得和价格
    function ExactInputSingle(ContractCalculateIn memory _CalculateData)external view returns (ExactResult memory _ExactResult){
        uint24 curfee9975 =_CalculateData.Fee9975;
        int24 tick = TickMath.getTickAtSqrtRatio(_CalculateData.SqrtPrice);
        int24 tickSpacing = IPancakePairV3(_CalculateData.Pair).tickSpacing();
        uint128 startLiquidity = IPancakePairV3(_CalculateData.Pair).liquidity();
        SwapState memory state = SwapState({
            tokenIn:_CalculateData.TokenIn,
            tokenOut:_CalculateData.TokenOut,
            fee2500:(10000 - _CalculateData.Fee9975) * 100, //2500
            amountSpecifiedRemaining: _CalculateData.AmountIn,
            amountCalculated: 0,
            sqrtPriceX96: _CalculateData.SqrtPrice,
            sqrtTargetX96:AMethodContract.GetNextTickSqrtPriceX96(_CalculateData.TokenIn,_CalculateData.TokenOut,tick,tickSpacing),
            tick: tick,
            lastliquidity:startLiquidity,
            liquidity: startLiquidity
        });
        
        while(true){
            try this.GetAmountInAndOut(state.tokenIn, state.tokenOut, curfee9975, state.sqrtPriceX96, state.sqrtTargetX96, state.liquidity) returns (
                uint256 amountAreaIn,
                uint256 amountAreaOut,
                uint128 endLiquidity,
                int24 tickCurrent
            ) {
                if (state.amountSpecifiedRemaining > amountAreaIn) {
                    state.amountSpecifiedRemaining -= amountAreaIn;
                    state.amountCalculated += amountAreaOut;
                    state.lastliquidity = state.liquidity;
                    state.liquidity = endLiquidity;
                    state.tick = tickCurrent;
                    state.sqrtPriceX96 = state.sqrtTargetX96;
                    state.sqrtTargetX96 = AMethodContract.GetNextTickSqrtPriceX96(state.tokenIn,state.tokenOut,state.tick,tickSpacing);
                }else if (state.amountSpecifiedRemaining == amountAreaIn){
                    state.amountSpecifiedRemaining -= amountAreaIn;
                    state.amountCalculated += amountAreaOut;
                    state.lastliquidity = state.liquidity;
                    state.liquidity = endLiquidity;
                    state.tick = tickCurrent;
                    state.sqrtPriceX96 = state.sqrtTargetX96;
                    break;
                }else{
                    break;
                }
            } catch {
                break;
            }
        }
        uint160 sqrtPriceX96After;
        if (state.amountSpecifiedRemaining != 0){
            if (_CalculateData.TokenIn < _CalculateData.TokenOut){
                //J目标 = 10000*L*J初始*1000000000000/(p*投入*J初始/2^96 + 10000*L)/1000000000000
                sqrtPriceX96After = uint160(uint256(10000*uint256(state.lastliquidity)*state.sqrtPriceX96)*1000000000000/(uint256(curfee9975)*state.amountSpecifiedRemaining*uint256(state.sqrtPriceX96)/X96 + uint256(10000*state.lastliquidity))/1000000000000); //最不够精确 正11 负4
            }else{
                //J目标 = 2^96*p*投入*1000000000000/(10000*L)/1000000000000 + J初始
                sqrtPriceX96After = uint160(X96*uint256(curfee9975)*state.amountSpecifiedRemaining*1000000000000/uint256(10000*state.lastliquidity)/1000000000000 + uint256(state.sqrtPriceX96)); //稍稍不够精确 正9 负7 -11
            }
            (,uint256 out,,)= this.GetAmountInAndOut(state.tokenIn, state.tokenOut, curfee9975, state.sqrtPriceX96, sqrtPriceX96After, state.lastliquidity);
            state.amountCalculated += out;
        }else{
            sqrtPriceX96After = state.sqrtPriceX96;
        }
        _ExactResult.Amount = state.amountCalculated;
        _ExactResult.SqrtPrice = sqrtPriceX96After;
        _ExactResult.Liquidity = state.liquidity;
        _ExactResult.Tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96After);
        // amountOut = state.amountCalculated;
        // liquidity = state.liquidity;
        // afterTick = state.tick;
    }
}
