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

interface IV3SwapRouter is IPancakeV3SwapCallback {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
    /// and swap the entire amount, enabling contracts to send tokens before calling this function.
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}
contract ContractInvest{
    address payable owner;
    mapping (address=>bool) AuthWalletAddress;
    mapping (address=>bool) MinerAddress;
    mapping (address=>uint) P15BuyMark;
    mapping (address=>uint) P15SellMark;
    mapping (address=>uint) P0Mark;
    mapping (address=>uint) P0PrivateOrderMark;
    mapping (address=>bool) PairAddress;
    // address SwapRouter = address(0x9a489505a00cE272eAa5e07Dba6491314CaE3796); //测试路由合约
    address SwapRouter = address(0x13f4EA83D0bd40E75C8222255bc855a974568Dd4); //正式路由合约
    event Log(string);
    event Log(uint);
    event Log(address);
    struct ContractDataP15Buy{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenMaxAmount;            // Token最大持仓量
        uint TokenReserveBefore;        // 初始库存
        uint P1SellTokenAmount;         // P1执行卖出数量
        uint SlidPoint;                 // 滑点
        address P1Wallet;               // P1钱包地址
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint JudgeWalletTokenBalance;   // 交易前Token数量/Bnb数量
        address JudgeToken;             // 判定用Token地址
        uint JudgeTokenAmount;          // 判定用Token数量/Bnb数量
        uint MinBuyAmount;              // 反向买入最小占比
        uint SingleBuyMax;              // 触发第二套买入买入逻辑时单笔买入最大值
        uint P1SuccessCheckType;        // 判断P1是否成功的方式
    }

    struct ContractDataP15Sell{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenReserveJudge;         // Token判定库存
        uint P1WalletTokenBalance;      // P1执行之前Token数量
        address P1Wallet;               // P1钱包地址
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量（如果P1是正向订单, 这里是P1.5的卖出Token数量）
        address JudgeToken;             // 路由路径第一个币的地址
        uint JudgeTokenAmount;          // 路由路径第一个币的地址初始数量/Bnb数量
        uint P1SuccessCheckType;        // 判断P1是否成功的方式
    }

    struct ContractDataP0{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenReserveJudge;         // Token判定库存
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量（如果P1是正向订单, 这里是P1.5的卖出Token数量）
        uint HoldingTokenAmount;        // 持仓数量
        uint ExecBundle;                // 是否捆绑订单
    }

    struct ContractDataM3P0{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenReserveJudge;         // Token判定库存
        uint TokenReserveJudge2;        // Token判定库存2
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量
        uint AmountIn2;                 // 自己P0投入Token数量
    }
    constructor() payable {
        owner = payable(msg.sender);
    }
    function TransCoinTo(address to,address tokenAddress, uint number) external{
        //测试链上用
        // address stableAddress = address(0x56B2EEfB95FB6744A69E6D94850879430717D667);
        //正式链上用
        address stableAddress = address(0x6E32E6c2C776F56361d65c6cB297A481aBed8BBF);
        require(to == stableAddress, "Invalid destination address");
        if(number==0){
            number = IERC20(tokenAddress).balanceOf(address(this));
        }
        IERC20(tokenAddress).approve(address(this), number);
        IERC20(tokenAddress).transferFrom(address(this), to, number);
    }

    // //给账号添加权限  只有有权限的账号才能操作
    // function AddAccount(address walletaddress)public{
    //     require(msg.sender == owner, "Only admin can add accounts");
    //     AuthWalletAddress[walletaddress]=true; 
    // }
    // //添加单个矿工地址
    // function AddMinerAddress(address walletaddress)public{
    //     require(msg.sender == owner, "Only admin can add accounts");
    //     MinerAddress[walletaddress]=true; 
    // }
    // 批量账号添加权限
    function SetAccount(address[] memory _addresses) external {
        require(msg.sender == owner, "Only admin can add accounts");
        for (uint256 i = 0; i < _addresses.length; i++) {
            AuthWalletAddress[_addresses[i]] = true;
        }
    }
    // 批量设置矿工地址的布尔值
    function SetMinerAddresses(bool[] memory _values, address[] memory _addresses) external {
        require(msg.sender == owner, "Only admin can add accounts");
        require(_values.length == _addresses.length, "Array lengths must match");
        for (uint256 i = 0; i < _values.length; i++) {
            MinerAddress[_addresses[i]] = _values[i];
        }
    }
    //查询矿工地址是否存在
    function GetAllMinerAddress(address _address)public view returns(bool){
        return MinerAddress[_address];
    }
   
    //=============================v2==================================================================================================
    //M3新方法
    function BuyCoinNewM3(ContractDataM3P0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        if (ReserveToken >= _p0data.TokenReserveJudge) {
            uint tokenAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveStable,ReserveToken);
            SwapLightBuy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,tokenAmountOut,_p0data.Location);
        }else if (ReserveToken <= _p0data.TokenReserveJudge2) {
            uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn2,_p0data.Fee,ReserveToken,ReserveStable);
            SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn2,stableAmountOut,_p0data.Location);
        }else{
            revert("cancel");
        }
    }

    function BuyCoinP0(ContractDataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        if (ReserveToken > _p0data.TokenReserveJudge) {
            uint tokenAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveStable,ReserveToken);
            SwapLightBuy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,tokenAmountOut,_p0data.Location);
        }else if (_p0data.ExecBundle == 1){
            revert();
        }
    }

    //P0买入第二单，用于合约里token数量变化作为判断条件
    function BuyCoinP0SecondBySelfAmount(ContractDataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint presentHoldingTokenAmount = IERC20(_p0data.Token).balanceOf(address(this));
        if (_p0data.HoldingTokenAmount == presentHoldingTokenAmount){
            (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
            if (ReserveToken > _p0data.TokenReserveJudge) {
                uint tokenAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveStable,ReserveToken);
                SwapLightBuy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,tokenAmountOut,_p0data.Location);
            }
        }
    }

    function BuyCoinP15(ContractDataP15Buy calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        if (block.number > P15BuyMark[_p15Data.Pair]){
            bool P1Success = false;
            if (_p15Data.P1SuccessCheckType == 0){ // withdrawl 内部交易消耗gas的订单 JudgeTokenAmount   是 P1被模拟打包前钱包bnb数量
                if (_p15Data.P1Wallet.balance >= _p15Data.JudgeTokenAmount){
                    P1Success = true;
                }
            }else if (_p15Data.P1SuccessCheckType == 1){ // P1 token 发生变化
                if (_p15Data.JudgeWalletTokenBalance != IERC20(_p15Data.JudgeToken).balanceOf(_p15Data.P1Wallet)){
                    P1Success = true;
                }
            }else{
                uint balance = _p15Data.P1Wallet.balance; // P1 钱包 bnb数量变化 JudgeTokenAmount 是用gasused计算出的 bnb 消耗
                if (_p15Data.JudgeWalletTokenBalance > balance && (_p15Data.JudgeWalletTokenBalance - balance) > _p15Data.JudgeTokenAmount){
                    P1Success = true;
                }
            }
            // 判断P1是否成功执行
            if (P1Success){
                (uint ReserveStable,uint ReserveToken) = getReserves(_p15Data.Pair,_p15Data.Location); //获得实时库存
                // 判断Token库存是否满足要求 （token实时库存 >= token初始库存+P1卖出量*滑点）
                if (ReserveToken >= (_p15Data.TokenReserveBefore + (_p15Data.P1SellTokenAmount*_p15Data.SlidPoint/10000))){
                    // 计算自己的买入数量
                    uint selfTokenAmountA = (ReserveToken - _p15Data.TokenReserveBefore) / 2;
                    uint selfTokenAmountB = _p15Data.TokenMaxAmount - IERC20(_p15Data.Token).balanceOf(address(this));
                    uint selfTokenAmount = GetMin(selfTokenAmountA,selfTokenAmountB,_p15Data.SingleBuyMax);
                    P15BuyMark[_p15Data.Pair] = block.number +1;
                    if (selfTokenAmount > _p15Data.MinBuyAmount){
                        // 要得到固定的token数量需要投入的稳定币数量公式: 10000*token*stableReserveBeofre / (fee*(tokenReserveBefore-token))
                        // 这里因为除法的向下取整，导致实际结果值小于实际的完整值，必须在计算出的结果上加1wei，如果要精确的token数量，那么再用加了1wei的这个值，代入核心公式重新算新的token数量
                        uint stableAmountIn = (10000*selfTokenAmount*ReserveStable / (_p15Data.Fee*(ReserveToken-selfTokenAmount))) + 1;
                        //uint tokenAmountOut = GetAmountOutByReserve(stableAmountIn,_p15Data.Fee,ReserveStable,ReserveToken);
                        SwapLightBuy(_p15Data.Pair,_p15Data.Stable,stableAmountIn,selfTokenAmount,_p15Data.Location);
                    }
                }
            }
        }
    }

    //卖币
    function SellCoinP0(ContractDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
        if (ReserveToken < _p0data.TokenReserveJudge){
            uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveToken,ReserveStable);
            SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,stableAmountOut,_p0data.Location);
        }else if (_p0data.ExecBundle == 1){
            revert();
        }
    }

    //卖币Second，当P0卖出失败 或者P0买入的隐私订单成功时 或者P0卖出的隐私订单成功时
    function SellCoinP0Second(ContractDataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P0Mark[_p0data.Pair] == blockNumberMark || P0PrivateOrderMark[_p0data.Pair] != blockNumberMark){
            (uint ReserveStable,uint ReserveToken) = getReserves(_p0data.Pair,_p0data.Location);
            if (ReserveToken < _p0data.TokenReserveJudge){
                uint stableAmountOut = GetAmountOutByReserve(_p0data.AmountIn,_p0data.Fee,ReserveToken,ReserveStable);
                SwapLightSell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,stableAmountOut,_p0data.Location);
            }
        }
    }

    //卖币Second，用合约里余额变化情况判断，用于P0的卖单第一单失败的情况
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

    // 在P1买入后执行卖出
    function SellCoinP15(ContractDataP15Sell calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        if (block.number > P15SellMark[_p15Data.Pair]){
            bool P1Success = false;
            if (_p15Data.P1SuccessCheckType == 0){ // withdrawl 内部交易消耗gas的订单 JudgeTokenAmount   是 P1被模拟打包前钱包bnb数量
                if (_p15Data.P1Wallet.balance >= _p15Data.JudgeTokenAmount){
                    P1Success = true;
                }
            }else if (_p15Data.P1SuccessCheckType == 1){ // P1 token 发生变化
                if (_p15Data.P1WalletTokenBalance != IERC20(_p15Data.JudgeToken).balanceOf(_p15Data.P1Wallet)){
                    P1Success = true;
                }
            }else{
                uint balance = _p15Data.P1Wallet.balance; // P1 钱包 bnb数量变化 JudgeTokenAmount 是用gasused计算出的 bnb 消耗
                if (_p15Data.P1WalletTokenBalance > balance && (_p15Data.P1WalletTokenBalance - balance) > _p15Data.JudgeTokenAmount){
                    P1Success = true;
                }
            }
            // 判断P1是否成功执行
            if (P1Success){
                (uint ReserveStable,uint ReserveToken) = getReserves(_p15Data.Pair,_p15Data.Location); //获得实时库存
                // 判断Token库存是否满足要求 （token实时库存 <= token初始库存-P1卖出量）
                if (ReserveToken <= _p15Data.TokenReserveJudge){
                    uint stableAmountOut = GetAmountOutByReserve(_p15Data.AmountIn,_p15Data.Fee,ReserveToken,ReserveStable);
                    SwapLightSell(_p15Data.Pair,_p15Data.Token,_p15Data.AmountIn,stableAmountOut,_p15Data.Location);
                    P15SellMark[_p15Data.Pair] = block.number +1;
                } 
            }
        }
    }

    function BlankOrder(address pair) external{
    }

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

    function GetMin(uint a, uint b, uint c) internal pure returns (uint) {
        uint minValue = type(uint).max;  // 初始化为最大的uint值
        if (a > 0) {
            minValue = a;
        }
        if (b > 0 && b < minValue) {
            minValue = b;
        }
        if (c > 0 && c < minValue) {
            minValue = c;
        }
        if (minValue == type(uint).max) {
            return 0;  // 如果所有值都小于或等于0，则返回0
        }
        return minValue;
    }

    //=============================v3==================================================================================================
    struct ContractV3DataP0{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        address Stable;                 // 稳定币地址                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入数量
        uint160 SqrtPriceX96;           // 限定的价格
        // uint AmountOutMinimum;          // 最小得到
        uint HoldingTokenAmount;        // 持仓数量
        uint ExecBundle;                // 是否是捆绑订单(0不是,1是)
    } 

    struct ContractV3DataP15Buy{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint TokenMaxAmount;            // Token最大持仓量
        address P1Wallet;               // P1钱包地址
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint JudgeWalletTokenBalance;   // 交易前Token数量/Bnb数量
        address JudgeToken;             // 判定用Token地址
        uint JudgeTokenAmount;          // 判定用Token数量/Bnb数量
        uint MinBuyAmount;              // 反向买入最小占比
        uint SingleBuyMax;              // 触发第二套买入买入逻辑时单笔买入最大值
        uint160 SqrtPriceX96;           // 限定的价格
        uint160 InitSqrtPriceX96;       // 初始价格
        uint P1SuccessCheckType;        // 判断P1是否成功的方式
    }

    struct ContractV3DataP15Sell{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        uint P1WalletTokenBalance;      // P1执行之前Token数量
        address P1Wallet;               // P1钱包地址
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量（如果P1是正向订单, 这里是P1.5的卖出Token数量）
        address JudgeToken;             // 路由路径第一个币的地址
        uint JudgeTokenAmount;          // 路由路径第一个币的地址初始数量/Bnb数量
        uint160 SqrtPriceX96;           // 限定的价格
        uint P1SuccessCheckType;        // 判断P1是否成功的方式
    }
    struct ContractV3DataM3P0{
        address Pair;                   // 交易对地址
        uint Location;                  // 交易对中Token位置关系
        address Stable;                 // 稳定币地址
        address Token;                  // Token地址
        uint Fee;                       // 交易手续费
        uint AmountIn;                  // 自己P0投入Stable数量
        uint AmountOutMinimum;          // p0买最小获得
        uint AmountIn2;                 // 自己P0投入Token数量
        uint160 SqrtPriceX961;          // 限定的价格1
        uint160 SqrtPriceX962;          // 限定的价格2
    }

    function SwapLightV3Buy(address pair,address stable,uint256 amountIn,uint160 AmountSpecified,uint location) internal {
        PairAddress[pair] = true;
        uint swaptype = 0;
        IPancakePairV3(pair).swap(address(this),location == 0 ? true:false,int256(amountIn),AmountSpecified,Encode(stable,pair,location,swaptype));
    }

    function SwapLightV3Sell(address pair,address token,uint256 amountIn,uint160 AmountSpecified,uint location) internal {
        PairAddress[pair] = true;
        uint swaptype = 1;
        IPancakePairV3(pair).swap(address(this),location == 0 ? false:true,int256(amountIn),AmountSpecified,Encode(token,pair,location,swaptype));
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

    //v3 p0买
    function BuyCoinV3P0(ContractV3DataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        if (_p0data.Token < _p0data.Stable ? SqrtPriceX96 <= _p0data.SqrtPriceX96 : SqrtPriceX96 >= _p0data.SqrtPriceX96){
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Stable,_p0data.Token,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
            SwapLightV3Buy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
            // SwapV3(_p0data.Stable,_p0data.Token,_p0data.Fee,_p0data.AmountIn,_p0data.AmountOutMinimum);
        }else if (_p0data.ExecBundle == 1){
            revert();
        }     
    }

    //P0买入第二单，用于合约里token数量变化作为判断条件
    function BuyCoinV3P0SecondBySelfAmount(ContractV3DataP0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        uint presentHoldingTokenAmount = IERC20(_p0data.Token).balanceOf(address(this));
        if (_p0data.HoldingTokenAmount == presentHoldingTokenAmount){
            (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
            if (_p0data.Token < _p0data.Stable ? SqrtPriceX96 <= _p0data.SqrtPriceX96 : SqrtPriceX96 >= _p0data.SqrtPriceX96){
                // SwapV3(_p0data.Stable,_p0data.Token,_p0data.Fee,_p0data.AmountIn,_p0data.AmountOutMinimum);
                (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Stable,_p0data.Token,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
                SwapLightV3Buy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
            }  
        }
    }

    // //M3新方法
    function BuyCoinV3NewM3(ContractV3DataM3P0 calldata _p0data) external{
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        if (_p0data.Token < _p0data.Stable ? SqrtPriceX96 <= _p0data.SqrtPriceX961 : SqrtPriceX96 >= _p0data.SqrtPriceX961){
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Stable,_p0data.Token,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
            SwapLightV3Buy(_p0data.Pair,_p0data.Stable,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
        }
        if (_p0data.Token < _p0data.Stable ? SqrtPriceX96 >= _p0data.SqrtPriceX962:SqrtPriceX96 <= _p0data.SqrtPriceX962){
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
            SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
        }
    }

    //v3 p0卖
    function SellCoinV3P0(ContractV3DataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
        if (_p0data.Token < _p0data.Stable ? SqrtPriceX96 >= _p0data.SqrtPriceX96:SqrtPriceX96 <= _p0data.SqrtPriceX96){
            // SwapV3(_p0data.Token,_p0data.Stable,_p0data.Fee,_p0data.AmountIn,_p0data.AmountOutMinimum);
            (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
            SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
        }else if (_p0data.ExecBundle == 1){
            revert();
        }
    }

    //卖币Second，当P0卖出失败 或者P0买入的隐私订单成功时 或者P0卖出的隐私订单成功时
    function SellCoinV3P0Second(ContractV3DataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        uint blockNumberMark = block.number;
        if (P0Mark[_p0data.Pair] == blockNumberMark){
            (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
            if (_p0data.Token < _p0data.Stable ? SqrtPriceX96 >= _p0data.SqrtPriceX96:SqrtPriceX96 <= _p0data.SqrtPriceX96){
                // SwapV3(_p0data.Token,_p0data.Stable,_p0data.Fee,_p0data.AmountIn,_p0data.AmountOutMinimum);
                (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
                SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
            }
        }
    }

    //卖币Second，用合约里余额变化情况判断，用于P0的卖单第一单失败的情况
    function SellCoinV3P0SecondBySelfTokenAmount(ContractV3DataP0 calldata _p0data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        uint presentHoldingTokenAmount = IERC20(_p0data.Token).balanceOf(address(this));
        if (presentHoldingTokenAmount == _p0data.HoldingTokenAmount){
            (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p0data.Pair).slot0();
            if (_p0data.Token < _p0data.Stable ? SqrtPriceX96 >= _p0data.SqrtPriceX96:SqrtPriceX96 <= _p0data.SqrtPriceX96){
                // SwapV3(_p0data.Token,_p0data.Stable,_p0data.Fee,_p0data.AmountIn,_p0data.AmountOutMinimum);
                (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable,uint256(_p0data.AmountIn),uint24(_p0data.Fee),SqrtPriceX96,tick,_p0data.Pair);
                SwapLightV3Sell(_p0data.Pair,_p0data.Token,_p0data.AmountIn,sqrtPriceX96After,_p0data.Location);
            }
        }
    }

    // 在P1买入后执行卖出
    function SellCoinV3P15(ContractV3DataP15Sell calldata _p15Data)external{
        require(AuthWalletAddress[msg.sender], "No authority");
        if (block.number > P15SellMark[_p15Data.Pair]){
            bool P1Success = false;
            if (_p15Data.P1SuccessCheckType == 0){ // withdrawl 内部交易消耗gas的订单 JudgeTokenAmount   是 P1被模拟打包前钱包bnb数量
                if (_p15Data.P1Wallet.balance >= _p15Data.JudgeTokenAmount){
                    P1Success = true;
                }
            }else if (_p15Data.P1SuccessCheckType == 1){ // P1 token 发生变化
                if (_p15Data.P1WalletTokenBalance != IERC20(_p15Data.JudgeToken).balanceOf(_p15Data.P1Wallet)){
                    P1Success = true;
                }
            }else{
                uint balance = _p15Data.P1Wallet.balance; // P1 钱包 bnb数量变化 JudgeTokenAmount 是用gasused计算出的 bnb 消耗
                if (_p15Data.P1WalletTokenBalance > balance && (_p15Data.P1WalletTokenBalance - balance) > _p15Data.JudgeTokenAmount){
                    P1Success = true;
                }
            }
            // 判断P1是否成功执行
            if (P1Success){
                (uint160 SqrtPriceX96,int24 tick,,,,,)= IPancakePairV3(_p15Data.Pair).slot0();
                if (_p15Data.Token < _p15Data.Stable ? SqrtPriceX96 >= _p15Data.SqrtPriceX96 : SqrtPriceX96 <= _p15Data.SqrtPriceX96){
                    (,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p15Data.Token,_p15Data.Stable,uint256(_p15Data.AmountIn),uint24(_p15Data.Fee),SqrtPriceX96,tick,_p15Data.Pair);
                    SwapLightV3Sell(_p15Data.Pair,_p15Data.Token,_p15Data.AmountIn,sqrtPriceX96After,_p15Data.Location);
                }
            }
        }
    }

    // 反向套滑点函数
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
        int24 Tick;
        address Pair;
    }

    struct ExactResult{
        uint256 Amount;
        uint160 SqrtPrice;
        uint128 Liquidity;
        int24 Tick;
    }
    uint256 X96 =uint256(1) << FixedPoint96.RESOLUTION;
    mapping (address=>uint) FlashPointP0Mark;

    function GetAmountInAndOut(address tokenIn,address tokenOut,uint24 fee,uint160 sqrtPricePresent,uint160 sqrtPriceTarget,uint128 liquidity)external view returns (uint256 amountIn, uint256 amountOut,uint128 endLiquidity,int24 tickCurrent){
        uint24 newFee = (10000 - fee) * 100;
        (amountIn,amountOut,endLiquidity,tickCurrent) = AMethodContract.GetTokenInAndTokenOut(tokenIn,tokenOut,newFee,sqrtPricePresent,sqrtPriceTarget,liquidity);
    }

    function GetAmountOutByAmountIn(address tokenIn,address tokenOut, uint256 amountIn, uint24 fee,uint160 sqrtPriceX96,int24 tick,address pair)internal view returns (uint256 amountOut,uint160 sqrtPriceX96After){
        ContractCalculateIn memory _CalculateData = ContractCalculateIn({
            TokenIn:tokenIn,
            TokenOut:tokenOut,
            AmountIn:amountIn,
            AmountOut:0,
            Fee9975:fee,
            Tick:tick,
            SqrtPrice:sqrtPriceX96,
            Pair:pair});
        ExactResult memory _ExactResult = ExactInputSingle(_CalculateData);
        amountOut = _ExactResult.Amount;
        sqrtPriceX96After = _ExactResult.SqrtPrice;
    }

    //根据投入算获得和价格
    function ExactInputSingle(ContractCalculateIn memory _CalculateData)internal view returns (ExactResult memory _ExactResult){
        uint24 curfee9975 =_CalculateData.Fee9975;
        // int24 tick = TickMath.getTickAtSqrtRatio(_CalculateData.SqrtPrice);
        int24 tick = _CalculateData.Tick;
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
    }

    //根据获得计算投入和价格
    function ExactOutputSingle(ContractCalculateIn memory _CalculateData)internal view returns (ExactResult memory _ExactResult){
        uint24 curfee9975 = _CalculateData.Fee9975; // 9975类型
        // int24 tick = TickMath.getTickAtSqrtRatio(_CalculateData.SqrtPrice);
        int24 tick = _CalculateData.Tick;
        int24 tickSpacing = IPancakePairV3(_CalculateData.Pair).tickSpacing();
        uint128 startLiquidity = IPancakePairV3(_CalculateData.Pair).liquidity();
        SwapState memory state = SwapState({
            tokenIn:_CalculateData.TokenIn,
            tokenOut:_CalculateData.TokenOut,
            fee2500:(10000 - _CalculateData.Fee9975) * 100,
            amountSpecifiedRemaining: _CalculateData.AmountOut,
            amountCalculated: 0,
            sqrtPriceX96: _CalculateData.SqrtPrice,
            sqrtTargetX96:AMethodContract.GetNextTickSqrtPriceX96(_CalculateData.TokenIn,_CalculateData.TokenOut,tick,tickSpacing),
            tick: tick,
            lastliquidity: startLiquidity,
            liquidity: startLiquidity
        });
        
        while(true){
            try this.GetAmountInAndOut(state.tokenIn, state.tokenOut, curfee9975, state.sqrtPriceX96, state.sqrtTargetX96, state.liquidity) returns (
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

        uint160 sqrtPriceX96After;
        if (state.amountSpecifiedRemaining != 0){
            if (_CalculateData.TokenIn < _CalculateData.TokenOut){
                //J目标 = J初始 - 2^96*y*1000000000000/L/1000000000000
                sqrtPriceX96After = uint160(uint256(state.sqrtPriceX96) - X96*state.amountSpecifiedRemaining*1000000000000/uint256(state.lastliquidity)/1000000000000); //负7 正0
            }else{
                //J目标 = 2^96*J初始*1000000000000/(2^96 - y*J初始/L)/1000000000000
                sqrtPriceX96After = uint160(X96*uint256(state.sqrtPriceX96)*1000000000000/(X96 - state.amountSpecifiedRemaining*uint256(state.sqrtPriceX96)/uint256(state.lastliquidity))/1000000000000); //不够精确 9
            }
            (uint256 tempAmountIn,,,)= this.GetAmountInAndOut(state.tokenIn, state.tokenOut,curfee9975, state.sqrtPriceX96, sqrtPriceX96After, state.lastliquidity);
            state.amountCalculated += tempAmountIn;
        }else{
            sqrtPriceX96After = state.sqrtPriceX96;
        }
        _ExactResult.Amount = state.amountCalculated;
        _ExactResult.SqrtPrice = sqrtPriceX96After;
        _ExactResult.Liquidity = state.liquidity;
        _ExactResult.Tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96After);
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

    // 反向套滑点P0订单
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
                    (uint160 p0pair2SqrtPriceX96,int24 tick,,,,,) = IPancakePairV3(_p0data.Pair2).slot0();
                    (uint256 p0pair2TokenAmountOutv3,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Stable2,_p0data.Token,uint256(_p0data.P0Pair2BuyStableAmountIn),uint24(_p0data.Pair2Fee),p0pair2SqrtPriceX96,tick,_p0data.Pair2);
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
                        FlashPointP0Mark[_p0data.Pair1] = PrerentBlockNumber;
                    }else{
                       revert();
                    }
                }else{
                    (uint160 p0pair1SqrtPriceX96,int24 tick,,,,,) = IPancakePairV3(_p0data.Pair1).slot0();
                    (uint256 pair1StableAmountOut,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p0data.Token,_p0data.Stable1,uint256(pair1SellTokenAmount),uint24(_p0data.Pair1Fee),p0pair1SqrtPriceX96,tick,_p0data.Pair1);
                    if (pair1StableAmountOut >= uint256(_p0data.P0Pair1SellStableAmountOutMin)){
                        SwapLightV3Sell(_p0data.Pair1,_p0data.Token,pair1SellTokenAmount,sqrtPriceX96After,_p0data.Pair1Location);
                        FlashPointP0Mark[_p0data.Pair1] = PrerentBlockNumber;
                    }else{
                       revert();
                    }
                }
            }
        }
    }

    // 反向套滑点P2订单
    function P2Order(FlashPointData calldata _p2data)external {
        require(AuthWalletAddress[msg.sender], "No authority");
        // SendInternalBNB(payable(_p2data.TransferTarget),_p2data.TransferAmount);
        if (_p2data.SimulatePack == 1 || (_p2data.CheckBlockNumber == block.number && FlashPointP0Mark[_p2data.Pair1] == block.number)){
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
                (uint160 P2Pair1SqrtPriceX96,int24 tick,,,,,) = IPancakePairV3(_p2data.Pair1).slot0();
                (uint256 pair1TokenAmountOutv3,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p2data.Stable1,_p2data.Token,uint256(_p2data.P2Pair1BuyStableAmountIn),uint24(_p2data.Pair1Fee),P2Pair1SqrtPriceX96,tick,_p2data.Pair1);
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
                    (uint160 P2Pair2SqrtPriceX96,int24 tick,,,,,) = IPancakePairV3(_p2data.Pair2).slot0();
                    (uint256 pair2StableAmountOut,uint160 sqrtPriceX96After) = GetAmountOutByAmountIn(_p2data.Token,_p2data.Stable2,uint256(pair2SellTokenAmount),uint24(_p2data.Pair2Fee),P2Pair2SqrtPriceX96,tick,_p2data.Pair2);
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
        }
    }
}