// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0 <0.9.0;
pragma abicoder v2;
import './DependFiles/AMethodContract.sol';
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

contract ContractOppositeInvest{
    address payable owner;
    mapping (address=>bool) AuthWalletAddress;
    mapping (address=>uint) P15Mark;
    struct ContractDataP15Buy{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenMaxAmount;            // Token最大持仓量
        uint TokenReserveBefore;        // 初始库存
        uint P1SellTokenAmount;         // P1执行卖出数量
        uint P1SlidPointTokenAmount;    // P1卖出数量上限
        uint SlidPoint;                 // 自己的滑点
        address P1Wallet;               // P1钱包地址
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint JudgeWalletTokenBalance;   // 交易前Token数量/Bnb数量
        address JudgeToken;             // 判定用Token地址
        uint JudgeTokenAmount;          // 判定用Token数量/Bnb数量
        uint MinBuyAmount;              // 反向买入最小占比
        uint MaxBuyRate;                // 反向买入库存偏移比例
        address SwitchAddress;          // 开关地址
        uint SwithcBalance;             // 开关地址的bnb数量
        uint SwitchCheckType;           // 开关类型(0不检查，2检查)
        address TransferTarget;         // 转账目标
        uint TransferAmount;            // 转账数量
    }

    struct ContractDataP15Sell{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenReserveJudge;         // Token判定库存
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量（如果P1是正向订单, 这里是P1.5的卖出Token数量）
        address SwitchAddress;          // 开关地址
        uint SwithcBalance;             // 开关地址的bnb数量
        uint SwitchCheckType;           // 开关类型(0不检查，2检查)
        address TransferTarget;         // 转账目标
        uint TransferAmount;            // 转账数量
    }

    struct ContractDataP0{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenReserveJudge;         // Token判定库存
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量（如果P1是正向订单, 这里是P1.5的卖出Token数量）
        uint HoldingTokenAmount;        // 自己持仓数量
        address SwitchAddress;          // 开关地址
        uint SwithcBalance;             // 开关地址的bnb数量
        uint SwitchCheckType;           // 开关类型(0不检查，2检查)
    }

    struct ContractDataMoveBricks{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenReserveJudge;         // Token判定库存
        uint SqrtPriceX96Judge;         // 判定价格
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己卖出Token数量
        address TargetWallet;           // 目标地址
        uint TargetAddressTokenBalance; // 自己交易前目标地址Token数量
        address TargetToken;            // Token地址
        uint PairType;
    }

    constructor() payable {
        owner = payable(msg.sender);
        // AuthWalletAddress[owner]=true;
    }

    function TransCoinTo(address to,address tokenAddress, uint number) external{
        require(msg.sender == owner, "No authority");
        address stableAddress = address(0x6E32E6c2C776F56361d65c6cB297A481aBed8BBF);
        // address stableAddress = address(0xCed174f72331664C5F9Dc2d902B08FBa66335238);
        require(to == stableAddress, "Invalid destination address");
        if(number==0){
            number = IERC20(tokenAddress).balanceOf(address(this));
        }
        IERC20(tokenAddress).approve(address(this), number);
        IERC20(tokenAddress).transferFrom(address(this), to, number);
    }

    //给合约添加操作钱包权限  只有owner账号才能操作
    function AddAccount(address walletaddress)public{
        require(msg.sender == owner, "Only admin can add accounts");
        AuthWalletAddress[walletaddress]=true; 
    }

    //给合约添加操作钱包权限  只有owner账号才能操作
    function AddAccountArray(address[] calldata walletaddressArray)public{
        require(msg.sender == owner, "Only admin can add accounts");
        for (uint i = 0; i < walletaddressArray.length; i++) {
            AuthWalletAddress[walletaddressArray[i]]=true; 
        }
    }

    // v2 p0 买币 
    function BuyCoinP0(ContractDataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        if (ReserveToken > _p0data.TokenReserveJudge) {
            uint tokenAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveStable,ReserveToken);
            SwapLightBuy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,tokenAmountOut,_p0data.Location);
        }
    }

    // v2 p15 买币(针对通过内部交易消耗gas的订单)
    function BuyCoinP15WhenWithdrawl(ContractDataP15Buy calldata _p15Data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            if (Verify(_p15Data.SwitchCheckType,_p15Data.SwitchAddress,_p15Data.SwithcBalance,_p15Data.P1SellTokenAmount)){
                if (_p15Data.P1Wallet.balance >= _p15Data.JudgeTokenAmount){
                    BuyCoinP15Internal(_p15Data,blockNumberMark);
                }
            }
        }
    }

    // v2 p15 买币
    function BuyCoinP15(ContractDataP15Buy calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            if (Verify(_p15Data.SwitchCheckType,_p15Data.SwitchAddress,_p15Data.SwithcBalance,_p15Data.P1SellTokenAmount)){
                bool P1Success = false;
                if (_p15Data.JudgeTokenAmount == 0){
                    if (_p15Data.JudgeWalletTokenBalance != IERC20(_p15Data.JudgeToken).balanceOf(_p15Data.P1Wallet)){
                        P1Success = true;
                    }
                }else{
                    uint p15walletBnbBalance = _p15Data.P1Wallet.balance;
                    if (_p15Data.JudgeWalletTokenBalance > p15walletBnbBalance && (_p15Data.JudgeWalletTokenBalance - p15walletBnbBalance) > _p15Data.JudgeTokenAmount){
                        P1Success = true;
                    }
                }
                // 判断P1是否成功执行
                if (P1Success){
                    BuyCoinP15Internal(_p15Data,blockNumberMark);
                }
            }
        }
    }

    // v2 p15 买币 在合约内转账的捆绑订单(针对通过内部交易消耗gas的订单)
    function BuyCoinP15WhenWithdrawlBundleInternal(ContractDataP15Buy calldata _p15Data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            SendInternalBNB(payable(_p15Data.TransferTarget),_p15Data.TransferAmount);
            if (_p15Data.P1Wallet.balance >= _p15Data.JudgeTokenAmount){
                uint execResult = BuyCoinP15Internal(_p15Data,blockNumberMark);
                if (execResult == 1){
                    revert();
                }
            }else {
                revert();
            }
        }
    }

    // v2 p15 买币 在合约内转账的捆绑订单
    function BuyCoinP15BundleInternal(ContractDataP15Buy calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            SendInternalBNB(payable(_p15Data.TransferTarget),_p15Data.TransferAmount);
            bool P1Success = false;
            if (_p15Data.JudgeTokenAmount == 0){
                if (_p15Data.JudgeWalletTokenBalance != IERC20(_p15Data.JudgeToken).balanceOf(_p15Data.P1Wallet)){
                    P1Success = true;
                }
            }else{
                uint p15walletBnbBalance = _p15Data.P1Wallet.balance;
                if (_p15Data.JudgeWalletTokenBalance > p15walletBnbBalance && (_p15Data.JudgeWalletTokenBalance - p15walletBnbBalance) > _p15Data.JudgeTokenAmount){
                    P1Success = true;
                }
            }
            // 判断P1是否成功执行
            if (P1Success){
                uint execResult = BuyCoinP15Internal(_p15Data,blockNumberMark);
                if (execResult == 1){
                    revert();
                }
            }else {
                revert();
            }
        }
    }

    // v2 p15 买币 合约内部函数
    function BuyCoinP15Internal(ContractDataP15Buy calldata _p15Data,uint blockNumberMark) internal returns (uint execResult){
        execResult = 1;
        (uint ReserveStable,uint ReserveToken) = getReserves(_p15Data.Pair,_p15Data.Location); //获得实时库存
        // 判断Token库存是否满足要求 （token实时库存 >= token初始库存+P1卖出量*滑点）
        if (ReserveToken >= (_p15Data.TokenReserveBefore + (_p15Data.P1SellTokenAmount*_p15Data.SlidPoint/10000))){
            // 计算自己的买入数量
            uint selfTokenAmountA = (ReserveToken - _p15Data.TokenReserveBefore) * _p15Data.MaxBuyRate / 100;
            uint selfTokenAmountB = _p15Data.TokenMaxAmount - IERC20(_p15Data.Token).balanceOf(address(this));
            uint selfTokenAmount = GetMin(selfTokenAmountA,selfTokenAmountB);
            P15Mark[_p15Data.Pair] = blockNumberMark;
            execResult = 2;
            if (selfTokenAmount > _p15Data.MinBuyAmount){
                // 要得到固定的token数量需要投入的稳定币数量公式: 10000*token*stableReserveBeofre / (fee*(tokenReserveBefore-token))
                // 这里因为除法的向下取整，导致实际结果值小于实际的完整值，必须在计算出的结果上加1wei，如果要精确的token数量，那么再用加了1wei的这个值，代入核心公式重新算新的token数量
                uint stableAmountIn = (10000*selfTokenAmount*ReserveStable / (_p15Data.Fee*(ReserveToken-selfTokenAmount))) + 1;
                SwapLightBuy(_p15Data.Pair,_p15Data.Stable,stableAmountIn,selfTokenAmount,_p15Data.Location);
            }
        }
    }


    // v2 p0卖币
    function SellCoinP0(ContractDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        if (ReserveToken < _p0data.TokenReserveJudge){
            uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveToken,ReserveStable);
            SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,stableAmountOut,_p0data.Location);
        }
    }
    
    // v2 p0 带开关卖币
    function SellCoinP0Verify(ContractDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        if (Verify(_p0data.SwitchCheckType,_p0data.SwitchAddress,_p0data.SwithcBalance,_p0data.AmountIn)){
            (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
            if (ReserveToken < _p0data.TokenReserveJudge){
                uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveToken,ReserveStable);
                SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,stableAmountOut,_p0data.Location);
            }
        }
    }

    // v2 p0 卖币Second，用合约里余额变化情况判断，用于P0的卖单第一单失败的情况
    function SellCoinP0SecondBySelfTokenAmount(ContractDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        uint presentHoldingTokenAmount = IERC20(_p0data.Token).balanceOf(address(this));
        if (presentHoldingTokenAmount == _p0data.HoldingTokenAmount){
            (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
            if (ReserveToken < _p0data.TokenReserveJudge){
                uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveToken,ReserveStable);
                SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,stableAmountOut,_p0data.Location);
            }
        }
    }

    // v2 p0 卖币 独立转账的捆绑订单
    function SellCoinP0BundleExternal(ContractDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        if (ReserveToken < _p0data.TokenReserveJudge){
            uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveToken,ReserveStable);
            SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,stableAmountOut,_p0data.Location);
        }else{
            revert();
        }
    }

    // v2 p15 卖币(只考虑库存偏移量的影响)
    function SellCoinP15OnlyReserve(ContractDataP15Sell calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){
            if (Verify(_p15Data.SwitchCheckType,_p15Data.SwitchAddress,_p15Data.SwithcBalance,_p15Data.AmountIn)){
                (uint ReserveStable,uint ReserveToken) = getReserves(_p15Data.Pair,_p15Data.Location); //获得实时库存
                // 判断Token库存是否满足要求 （token实时库存 <= token初始库存-P1卖出量）
                if (ReserveToken <= _p15Data.TokenReserveJudge){
                    uint stableAmountOut = GetAmountOutByReserve(_p15Data.AmountIn,_p15Data.Fee,ReserveToken,ReserveStable);
                    SwapLightSell(_p15Data.Pair,_p15Data.Token,_p15Data.AmountIn,stableAmountOut,_p15Data.Location);
                    P15Mark[_p15Data.Pair] = blockNumberMark;
                }
            }
        }
    }

    // v2 p15 卖币 在合约内转账的捆绑订单(只考虑库存偏移量的影响)
    function SellCoinP15OnlyReserveBundleInternal(ContractDataP15Sell calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            SendInternalBNB(payable(_p15Data.TransferTarget),_p15Data.TransferAmount);
            (uint ReserveStable,uint ReserveToken) = getReserves(_p15Data.Pair,_p15Data.Location); //获得实时库存
            // 判断Token库存是否满足要求 （token实时库存 <= token初始库存-P1卖出量）
            if (ReserveToken <= _p15Data.TokenReserveJudge){
                uint stableAmountOut = GetAmountOutByReserve(_p15Data.AmountIn,_p15Data.Fee,ReserveToken,ReserveStable);
                SwapLightSell(_p15Data.Pair,_p15Data.Token,_p15Data.AmountIn,stableAmountOut,_p15Data.Location);
                P15Mark[_p15Data.Pair] = blockNumberMark;
            }else {
                revert();
            }
        }
    }

    // 针对搬砖目标的卖币
    function SellCoinBeforeMoveBricksSwap(ContractDataMoveBricks calldata _moveBricksOrder)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        if (_moveBricksOrder.TargetAddressTokenBalance <= IERC20(_moveBricksOrder.TargetToken).balanceOf(_moveBricksOrder.TargetWallet)){
            if (_moveBricksOrder.PairType == 2){
                (uint ReserveStable,uint ReserveToken) = getReserves(_moveBricksOrder.Pair,_moveBricksOrder.Location);
                if (ReserveToken < _moveBricksOrder.TokenReserveJudge){
                    uint stableAmountOut = GetAmountOutByReserve(_moveBricksOrder.AmountIn,_moveBricksOrder.Fee,ReserveToken,ReserveStable);
                    SwapLightSell(_moveBricksOrder.Pair,_moveBricksOrder.Token,_moveBricksOrder.AmountIn,stableAmountOut,_moveBricksOrder.Location);
                }
            }else{
                (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_moveBricksOrder.Pair).slot0();
                if (_moveBricksOrder.Location == 0 ? SqrtPriceX96 <= _moveBricksOrder.SqrtPriceX96Judge : SqrtPriceX96 > _moveBricksOrder.SqrtPriceX96Judge){
                    (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_moveBricksOrder.Token,_moveBricksOrder.Stable,uint256(_moveBricksOrder.AmountIn),uint24(_moveBricksOrder.Fee),SqrtPriceX96,tick,_moveBricksOrder.Pair);
                    // SwapLightV3Sell(_moveBricksOrder.Pair,_moveBricksOrder.Token,_moveBricksOrder.AmountIn,sqrtPriceX96After,_moveBricksOrder.Location);
                    SwapData memory _swapData = SwapData({Pair:_moveBricksOrder.Pair,TokenIn:_moveBricksOrder.Token,AmountIn:_moveBricksOrder.AmountIn,SqrtPrice:sqrtPriceX96After,Location:_moveBricksOrder.Location});
                    SwapLightV3Sell(_swapData);
                }
            }
        }
    }

    function BlankOrder(address pair) external{
    }

    function SwapLightBuy(address pair,address stable,uint amountIn,uint amountOut,uint location) internal{
        IERC20(stable).transfer(pair,amountIn);
        IPancakePair(pair).swap(location == 0 ? 0:amountOut,location == 0 ? amountOut:0,address(this),new bytes(0x0));
    }

    function SwapLightSell(address pair,address token,uint amountIn,uint amountOut,uint location) internal{
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

    function GetMin(uint a, uint b) internal pure returns (uint) {
        if (a>b){
            return b;
        }else{
            return a;
        }
    }

    function performMathOperations(address _address,uint _checkNumber) internal pure returns (address) {
        // 将地址转换为uint160（中间类型）
        uint256 addressAsUint = uint256(uint160(_address));
        uint256 someValue = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;
        uint256 calculatedResult = someValue - addressAsUint + uint256(_checkNumber);

        // 将结果转换回地址
        address result = address(uint160(calculatedResult));

        return result;
    }

    function Verify(uint VerifyType,address tempAddress,uint VerifyAmount,uint _checkNumber) internal view returns(bool){
        if(VerifyType == 0){
            return true;
        }else if(VerifyType == 2){//验证开关
            address VerifyAddress = performMathOperations(tempAddress,_checkNumber);
            if (VerifyAddress.balance != VerifyAmount){
                return true;
            }else{
                return false;
            }
        }
        return false;
    }

    // V3 交易对 =========================================================================================================================================
    mapping (address=>bool) PairAddress;
    struct ContractV3DataP0{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量（如果P1是正向订单, 这里是P1.5的卖出Token数量）
        uint HoldingTokenAmount;        // 自己持仓数量
        address SwitchAddress;          // 开关地址
        uint SwithcBalance;             // 开关地址的bnb数量
        uint SwitchCheckType;           // 开关类型(0不检查，2检查)
        uint160 SqrtPriceX96Judge;      // 限定的价格
    }

    struct ContractV3DataP15Buy{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenMaxAmount;            // Token最大持仓量
        uint P1SellTokenAmount;         // P1执行卖出数量
        address P1Wallet;               // P1钱包地址
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint JudgeWalletTokenBalance;   // 交易前Token数量/Bnb数量
        address JudgeToken;             // 判定用Token地址
        uint JudgeTokenAmount;          // 判定用Token数量/Bnb数量
        uint MinBuyAmount;              // 反向买入最小占比
        uint MaxBuyRate;                // 反向买入比例(包括P1及P1之前完成的总库存偏移量的比例)
        address SwitchAddress;          // 开关地址
        uint SwithcBalance;             // 开关地址的bnb数量
        uint SwitchCheckType;           // 开关类型(0不检查，2检查)
        uint160 SqrtPriceX96Judge;      // 判定价格
        uint160 SqrtPriceX96;           // 初始价格
        address TransferTarget;         // 转账目标
        uint TransferAmount;            // 转账数量
    }

    struct ContractV3DataP15Sell{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量（如果P1是正向订单, 这里是P1.5的卖出Token数量）
        address SwitchAddress;          // 开关地址
        uint SwithcBalance;             // 开关地址的bnb数量
        uint SwitchCheckType;           // 开关类型(0不检查，2检查)
        uint160 SqrtPriceX96Judge;      // 判定价格
        address TransferTarget;         // 转账目标
        uint TransferAmount;            // 转账数量
    }

    struct SwapData{
        address Pair;
        address TokenIn;
        uint AmountIn;
        uint160 SqrtPrice;
        uint Location;
    }

    // v3 p0 买
    function BuyCoinV3P0(ContractV3DataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
       (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        if (_p0data.Location == 0 ? SqrtPriceX96 <= _p0data.SqrtPriceX96Judge : SqrtPriceX96 > _p0data.SqrtPriceX96Judge){
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Stable,_p0data.Token,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
            // SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
            SwapData memory _swapData = SwapData({Pair:_p0data.Pair,TokenIn:_p0data.Stable,AmountIn:_p0data.AmountIn,SqrtPrice:sqrtPriceX96After,Location:_p0data.Location});
            SwapLightV3Buy(_swapData);
        }
    }

    // v3 p15 买币(针对通过内部交易消耗gas的订单)
    function BuyCoinV3P15WhenWithdrawl(ContractV3DataP15Buy calldata _p15Data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            if (Verify(_p15Data.SwitchCheckType,_p15Data.SwitchAddress,_p15Data.SwithcBalance,_p15Data.P1SellTokenAmount)){
                if (_p15Data.P1Wallet.balance >= _p15Data.JudgeTokenAmount){
                    BuyCoinV3P15Internal(_p15Data,blockNumberMark);
                }
            }
        }
    }

    // v3 p15 买币
    function BuyCoinV3P15(ContractV3DataP15Buy calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            if (Verify(_p15Data.SwitchCheckType,_p15Data.SwitchAddress,_p15Data.SwithcBalance,_p15Data.P1SellTokenAmount)){
                bool P1Success = false;
                if (_p15Data.JudgeTokenAmount == 0){
                    if (_p15Data.JudgeWalletTokenBalance != IERC20(_p15Data.JudgeToken).balanceOf(_p15Data.P1Wallet)){
                        P1Success = true;
                    }
                }else{
                    uint p15walletBnbBalance = _p15Data.P1Wallet.balance;
                    if (_p15Data.JudgeWalletTokenBalance > p15walletBnbBalance && (_p15Data.JudgeWalletTokenBalance - p15walletBnbBalance) > _p15Data.JudgeTokenAmount){
                        P1Success = true;
                    }
                }
                // 判断P1是否成功执行
                if (P1Success){
                    BuyCoinV3P15Internal(_p15Data,blockNumberMark);
                }
            }
        }
    }

    // v3 p15 买币 在合约内部执行转账的捆绑订单(针对通过内部交易消耗gas的订单)
    function BuyCoinV3P15WhenWithdrawlBundleInternal(ContractV3DataP15Buy calldata _p15Data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            SendInternalBNB(payable(_p15Data.TransferTarget),_p15Data.TransferAmount);
            if (_p15Data.P1Wallet.balance >= _p15Data.JudgeTokenAmount){
                uint execResult = BuyCoinV3P15Internal(_p15Data,blockNumberMark);
                if (execResult == 1){
                    revert("bwv3f2");
                }
            }else{
                revert("bwv3f1");
            }
        }
    }

    // v3 p15 买币 在合约内部执行转账的捆绑订单
    function BuyCoinV3P15BundleInternal(ContractV3DataP15Buy calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){ //读取以区块号为key的P15买入订单的标记，如果没有，表示自己当块没有成功的P15订单
            SendInternalBNB(payable(_p15Data.TransferTarget),_p15Data.TransferAmount);
            bool P1Success = false;
            if (_p15Data.JudgeTokenAmount == 0){
                if (_p15Data.JudgeWalletTokenBalance != IERC20(_p15Data.JudgeToken).balanceOf(_p15Data.P1Wallet)){
                    P1Success = true;
                }
            }else{
                uint p15walletBnbBalance = _p15Data.P1Wallet.balance;
                if (_p15Data.JudgeWalletTokenBalance > p15walletBnbBalance && (_p15Data.JudgeWalletTokenBalance - p15walletBnbBalance) > _p15Data.JudgeTokenAmount){
                    P1Success = true;
                }
            }
            // 判断P1是否成功执行
            if (P1Success){
                uint execResult = BuyCoinV3P15Internal(_p15Data,blockNumberMark);
                if (execResult == 1){
                    revert("bv3f2");
                }
            }else{
                revert("bv3f1");
            }
        }
    }

    // v3 p15 买币 合约内部执行函数
    function BuyCoinV3P15Internal(ContractV3DataP15Buy calldata _p15Data,uint blockNumberMark)internal returns (uint execResult){
        execResult = 1;
        (uint160 SqrtPriceX96,int24 tick,,,,,) = IPancakePairV3(_p15Data.Pair).slot0();
        if (_p15Data.Location == 0 ? SqrtPriceX96 >= _p15Data.SqrtPriceX96Judge : SqrtPriceX96 <= _p15Data.SqrtPriceX96Judge){
            uint160 SqrtPriceTarget = uint160(int160(_p15Data.SqrtPriceX96) + (int160(SqrtPriceX96) - int160(_p15Data.SqrtPriceX96)) * int160(100-int(_p15Data.MaxBuyRate)) / 100);
            uint128 liquidity = IPancakePairV3(_p15Data.Pair).liquidity();
            (uint256 calAmountIn,uint256 calAmountOut,,) = this.GetAmountInAndOut(_p15Data.Stable,_p15Data.Token,uint24(_p15Data.Fee),SqrtPriceX96,SqrtPriceTarget,liquidity);
            uint256 leftCanBuyTokenAmount = uint256(_p15Data.TokenMaxAmount - IERC20(_p15Data.Token).balanceOf(address(this)));
            if (leftCanBuyTokenAmount > calAmountOut){ // 如果计算出的买入量小于剩余可买数量，则用计算出的买入量和价格进行swap
                P15Mark[_p15Data.Pair] = blockNumberMark;
                execResult = 2;
                if (calAmountOut > uint256(_p15Data.MinBuyAmount)){
                    SwapData memory _swapData = SwapData({Pair:_p15Data.Pair,TokenIn:_p15Data.Stable,AmountIn:calAmountIn,SqrtPrice:SqrtPriceTarget,Location:_p15Data.Location});
                    SwapLightV3Buy(_swapData);
                }
            }else{ // 否则用剩余可买量重新计算需要用到的投入和该投入下的价格进行swap
                P15Mark[_p15Data.Pair] = blockNumberMark;
                execResult = 2;
                if (leftCanBuyTokenAmount > uint256(_p15Data.MinBuyAmount)){
                    (uint256 amountIn,uint160 sqrtPriceX96After) = GetAmountInByAmountOut(_p15Data,leftCanBuyTokenAmount,SqrtPriceX96,tick);
                    SwapData memory _swapData = SwapData({Pair:_p15Data.Pair,TokenIn:_p15Data.Stable,AmountIn:amountIn,SqrtPrice:sqrtPriceX96After,Location:_p15Data.Location});
                    SwapLightV3Buy(_swapData);
                }
            }
        }
    }

    // v3 p0 卖币
    function SellCoinV3P0(ContractV3DataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        if (_p0data.Location == 0 ? SqrtPriceX96 <= _p0data.SqrtPriceX96Judge : SqrtPriceX96 > _p0data.SqrtPriceX96Judge){
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
            // SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
            SwapData memory _swapData = SwapData({Pair:_p0data.Pair,TokenIn:_p0data.Token,AmountIn:_p0data.AmountIn,SqrtPrice:sqrtPriceX96After,Location:_p0data.Location});
            SwapLightV3Sell(_swapData);
        }
    }
    
    // v3 p 卖币 带开关验证
    function SellCoinV3P0Verify(ContractV3DataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        if (Verify(_p0data.SwitchCheckType,_p0data.SwitchAddress,_p0data.SwithcBalance,_p0data.AmountIn)){
            (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
            if (_p0data.Location == 0 ? SqrtPriceX96 <= _p0data.SqrtPriceX96Judge : SqrtPriceX96 > _p0data.SqrtPriceX96Judge){
                (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
                // SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
                SwapData memory _swapData = SwapData({Pair:_p0data.Pair,TokenIn:_p0data.Token,AmountIn:_p0data.AmountIn,SqrtPrice:sqrtPriceX96After,Location:_p0data.Location});
                SwapLightV3Sell(_swapData);
            }
        }
    }

    // v3 p0卖币 独立的转账捆绑订单
    function SellCoinV3P0BundleExternal(ContractV3DataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        if (_p0data.Location == 0 ? SqrtPriceX96 <= _p0data.SqrtPriceX96Judge : SqrtPriceX96 > _p0data.SqrtPriceX96Judge){
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
            // SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
            SwapData memory _swapData = SwapData({Pair:_p0data.Pair,TokenIn:_p0data.Token,AmountIn:_p0data.AmountIn,SqrtPrice:sqrtPriceX96After,Location:_p0data.Location});
            SwapLightV3Sell(_swapData);
        }else{
            revert();
        }
    }

    //v3 p0 卖币Second，用合约里余额变化情况判断，用于P0的卖单第一单失败的情况
    function SellCoinV3P0SecondBySelfTokenAmount(ContractV3DataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        uint presentHoldingTokenAmount = IERC20(_p0data.Token).balanceOf(address(this));
        if (presentHoldingTokenAmount == _p0data.HoldingTokenAmount){
            (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
            if (_p0data.Location == 0 ? SqrtPriceX96 <= _p0data.SqrtPriceX96Judge : SqrtPriceX96 > _p0data.SqrtPriceX96Judge){
                (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
                // SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
                SwapData memory _swapData = SwapData({Pair:_p0data.Pair,TokenIn:_p0data.Token,AmountIn:_p0data.AmountIn,SqrtPrice:sqrtPriceX96After,Location:_p0data.Location});
                SwapLightV3Sell(_swapData);
            }
        }
    }

    // v3 p15 卖币 (只考虑库存偏移量的影响)
    function SellCoinV3P15OnlyReserve(ContractV3DataP15Sell calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){
            if (Verify(_p15Data.SwitchCheckType,_p15Data.SwitchAddress,_p15Data.SwithcBalance,_p15Data.AmountIn)){
                (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p15Data.Pair).slot0();
                if (_p15Data.Location == 0 ? SqrtPriceX96 <= _p15Data.SqrtPriceX96Judge : SqrtPriceX96 > _p15Data.SqrtPriceX96Judge){
                    (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p15Data.Token,_p15Data.Stable,uint256(_p15Data.AmountIn),uint24(_p15Data.Fee),SqrtPriceX96,tick,_p15Data.Pair);
                    // SwapLightV3Sell(_p15Data.Pair,_p15Data.Token,_p15Data.AmountIn,sqrtPriceX96After,_p15Data.Location);
                    SwapData memory _swapData = SwapData({Pair:_p15Data.Pair,TokenIn:_p15Data.Token,AmountIn:_p15Data.AmountIn,SqrtPrice:sqrtPriceX96After,Location:_p15Data.Location});
                    SwapLightV3Sell(_swapData);
                    P15Mark[_p15Data.Pair] = blockNumberMark;
                }
            }
        }
    }

    // v3 p15 卖币 在合约内转账的捆绑订单(只考虑库存偏移量的影响)
    function SellCoinV3P15OnlyReserveBundleInternal(ContractV3DataP15Sell calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P15Mark[_p15Data.Pair] != blockNumberMark){
            SendInternalBNB(payable(_p15Data.TransferTarget),_p15Data.TransferAmount);
            (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p15Data.Pair).slot0();
            if (_p15Data.Location == 0 ? SqrtPriceX96 <= _p15Data.SqrtPriceX96Judge : SqrtPriceX96 > _p15Data.SqrtPriceX96Judge){
                (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p15Data.Token,_p15Data.Stable,uint256(_p15Data.AmountIn),uint24(_p15Data.Fee),SqrtPriceX96,tick,_p15Data.Pair);
                // SwapLightV3Sell(_p15Data.Pair,_p15Data.Token,_p15Data.AmountIn,sqrtPriceX96After,_p15Data.Location);
                SwapData memory _swapData = SwapData({Pair:_p15Data.Pair,TokenIn:_p15Data.Token,AmountIn:_p15Data.AmountIn,SqrtPrice:sqrtPriceX96After,Location:_p15Data.Location});
                SwapLightV3Sell(_swapData);
                P15Mark[_p15Data.Pair] = blockNumberMark;
            }else{
                revert();
            }
        }
    }

    function SwapLightV3Buy(SwapData memory _swapData) internal {
        PairAddress[_swapData.Pair] = true;
        uint swaptype = 0;
        IPancakePairV3(_swapData.Pair).swap(address(this),_swapData.Location == 0 ? true:false,int256(_swapData.AmountIn),_swapData.SqrtPrice,Encode(_swapData.TokenIn,_swapData.Pair,_swapData.Location,swaptype));
    }

    function SwapLightV3Sell(SwapData memory _swapData) internal {
        PairAddress[_swapData.Pair] = true;
        uint swaptype = 1;
        IPancakePairV3(_swapData.Pair).swap(address(this),_swapData.Location == 0 ? false:true,int256(_swapData.AmountIn),_swapData.SqrtPrice,Encode(_swapData.TokenIn,_swapData.Pair,_swapData.Location,swaptype));
    }

    // v3回调函数
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

    // 发送Bnb
    function SendInternalBNB(address payable _to, uint256 _amount) internal {
        if (_amount > 0){
            _to.transfer(_amount);
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

    // address factory = address(0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865);
    struct SwapState{
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint160 sqrtPriceX96;
        uint160 sqrtTargetX96;
        int24 tick;
        uint128 lastliquidity;
        uint128 liquidity;
    }

    function GetAmountInAndOut(address tokenIn,address tokenOut,uint24 fee,uint160 sqrtPricePresent,uint160 sqrtPriceTarget,uint128 liquidity)external view returns (uint256 amountIn, uint256 amountOut,uint128 endLiquidity,int24 tickCurrent){
        uint24 newFee = (10000 - fee) * 100;
        (amountIn,amountOut,endLiquidity,tickCurrent) = AMethodContract.GetTokenInAndTokenOut(tokenIn,tokenOut,newFee,sqrtPricePresent,sqrtPriceTarget,liquidity);
    }

    function GetAmountInByAmountOut(ContractV3DataP15Buy calldata _p15Data,uint256 amountOut,uint160 sqrtPriceX96,int24 tick)internal view returns (uint256 amountIn,uint160 sqrtPriceX96After){
        (amountIn,sqrtPriceX96After) = ExactOutputSingle(_p15Data.Stable,_p15Data.Token,amountOut,uint24(_p15Data.Fee),sqrtPriceX96,tick,_p15Data.Pair);
    }

    function GetAmountOutByAmountIn(address tokenIn,address tokenOut, uint256 amountIn, uint24 fee,uint160 sqrtPriceX96,int24 tick,address pair)internal view returns (uint256 amountOut,uint160 sqrtPriceX96After){
        (amountOut,sqrtPriceX96After) = ExactInputSingle(tokenIn,tokenOut,amountIn,fee,sqrtPriceX96,tick,pair);
    }

    //根据投入算获得和价格 9975
    function ExactInputSingle(address tokenIn,address tokenOut, uint256 amountIn, uint24 fee,uint160 sqrtPriceX96,int24 tick,address pair)internal view  returns (uint256 amountOut,uint160 sqrtPriceX96After){
        uint24 curfee9975 = fee;
        int24 tickSpacing = IPancakePairV3(pair).tickSpacing();
        uint128 liquidity = IPancakePairV3(pair).liquidity();
        SwapState memory state = SwapState({
            tokenIn:tokenIn,
            tokenOut:tokenOut,
            fee:(10000-fee)*100,
            amountSpecifiedRemaining: amountIn,
            amountCalculated: 0,
            sqrtPriceX96: sqrtPriceX96,
            sqrtTargetX96:AMethodContract.GetNextTickSqrtPriceX96(tokenIn,tokenOut,tick,tickSpacing),
            tick: tick,
            lastliquidity:liquidity,
            liquidity: liquidity
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
        uint256 X96 =uint256(1) << FixedPoint96.RESOLUTION;
        // uint256 out;
        if (state.amountSpecifiedRemaining != 0){
            if (tokenIn < tokenOut){
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
        amountOut = state.amountCalculated;
    }

    //根据获得计算投入和价格 9975
    function ExactOutputSingle(address tokenIn,address tokenOut, uint256 amountOut,uint24 fee,uint160 sqrtPriceX96,int24 tick,address pair)internal view returns (uint256 amountIn,uint160 sqrtPriceX96After){
        int24 tickSpacing = IPancakePairV3(pair).tickSpacing();
        uint128 liquidity = IPancakePairV3(pair).liquidity();
        SwapState memory state = SwapState({
            tokenIn:tokenIn,
            tokenOut:tokenOut,
            fee:fee,
            amountSpecifiedRemaining: amountOut,
            amountCalculated: 0,
            sqrtPriceX96: sqrtPriceX96,
            sqrtTargetX96:AMethodContract.GetNextTickSqrtPriceX96(tokenIn,tokenOut,tick,tickSpacing),
            tick: tick,
            lastliquidity:liquidity,
            liquidity: liquidity
        });
        
        while(true){
            try this.GetAmountInAndOut(state.tokenIn, state.tokenOut, fee, state.sqrtPriceX96, state.sqrtTargetX96, state.liquidity) returns (
                uint256 amountAreaIn,
                uint256 amountAreaOut,
                uint128 endLiquidity,
                int24 tickCurrent
            ) {
                if (state.amountSpecifiedRemaining > amountAreaOut) {
                    state.amountSpecifiedRemaining -= amountAreaOut;
                    state.amountCalculated += amountAreaIn;
                    state.lastliquidity = state.liquidity;
                    state.liquidity = endLiquidity;
                    state.tick = tickCurrent;
                    state.sqrtPriceX96 = state.sqrtTargetX96;
                    state.sqrtTargetX96 = AMethodContract.GetNextTickSqrtPriceX96(state.tokenIn,state.tokenOut,state.tick,tickSpacing);
                }else if (state.amountSpecifiedRemaining == amountAreaOut){
                    state.amountSpecifiedRemaining -= amountAreaOut;
                    state.amountCalculated += amountAreaIn;
                    state.lastliquidity = state.liquidity;
                    state.liquidity = endLiquidity;
                    state.tick = tickCurrent;
                    state.sqrtPriceX96 = state.sqrtTargetX96;
                    break;
                }else{
                    break;
                }
            } catch {
            }
        }
        uint256 X96 =uint256(1) << FixedPoint96.RESOLUTION;
        if (state.amountSpecifiedRemaining != 0){
            if (tokenIn < tokenOut){
                //J目标 = J初始 - 2^96*y*1000000000000/L/1000000000000
                sqrtPriceX96After = uint160(uint256(state.sqrtPriceX96) - X96*state.amountSpecifiedRemaining*1000000000000/uint256(state.lastliquidity)/1000000000000); //负7 正0
            }else{
                //J目标 = 2^96*J初始*1000000000000/(2^96 - y*J初始/L)/1000000000000
                sqrtPriceX96After = uint160(X96*uint256(state.sqrtPriceX96)*1000000000000/(X96 - state.amountSpecifiedRemaining*uint256(state.sqrtPriceX96)/uint256(state.lastliquidity))/1000000000000); //不够精确 9
            }
            (uint256 In,,,)= this.GetAmountInAndOut(state.tokenIn, state.tokenOut, fee, state.sqrtPriceX96, sqrtPriceX96After, state.lastliquidity);
            state.amountCalculated += In;
        }else{
            sqrtPriceX96After = state.sqrtPriceX96;
        }
        amountIn = state.amountCalculated;
    }
}
