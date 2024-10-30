// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0 <0.9.0;
pragma abicoder v2;
import './DependFiles/AMethodContract.sol';
import './DependFiles/TickMath.sol';

contract ContractFlashPointCalcu{
    uint256 X96 =uint256(1) << FixedPoint96.RESOLUTION;
    address Wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

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

    struct AmountInAndOutResult{
        uint256 amountIn;
        uint256 amountOut;
        uint128 endLiquidity;
        int24 tickCurrent;
        uint160 tickSqrtPrice;
    }

    struct PairData {
        address Pair;
        address Stable;
        address Token;
        uint24 Fee9975; 
        uint160 SqrtPrice;
        uint128 Liquidity;
        uint PairType;
        uint256 StableReserve;
        uint256 TokenReserve;
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

    function GetAmountOutByAmountIn(address tokenIn,address tokenOut, uint256 amountIn,uint24 fee,uint160 sqrtPriceX96,address pair)external view returns (uint256 amountOut,uint160 sqrtPriceX96After){
        ContractCalculateIn memory _CalculateData = ContractCalculateIn({TokenIn:tokenIn,TokenOut:tokenOut,AmountIn:amountIn,AmountOut:0,Fee9975:fee,SqrtPrice:sqrtPriceX96,Pair:pair});
        ExactResult memory _ExactResult = this.ExactInputSingle(_CalculateData);
        // (amountOut,sqrtPriceX96After,,) = this.ExactInputSingle(_CalculateData);
        amountOut = _ExactResult.Amount;
        sqrtPriceX96After = _ExactResult.SqrtPrice;
    }

    function GetAmountInByAmountOut(address tokenIn,address tokenOut,uint256 amountOut,uint24 fee,uint160 sqrtPriceX96,address pair)external view returns (uint256 amountIn,uint160 sqrtPriceX96After){
        ContractCalculateIn memory _CalculateData = ContractCalculateIn({TokenIn:tokenIn,TokenOut:tokenOut,AmountIn:0,AmountOut:amountOut,Fee9975:fee,SqrtPrice:sqrtPriceX96,Pair:pair});
        ExactResult memory _ExactResult = this.ExactOutputSingle(_CalculateData);
        // (amountIn,sqrtPriceX96After,,) = this.ExactOutputSingle(_CalculateData);
        amountIn = _ExactResult.Amount;
        sqrtPriceX96After = _ExactResult.SqrtPrice;
    }

    function GetAmountInAndOut(address tokenIn,address tokenOut,uint24 fee,uint160 sqrtPricePresent,uint160 sqrtPriceTarget,uint128 liquidity)external view returns (uint256 amountIn, uint256 amountOut,uint128 endLiquidity,int24 tickCurrent){
        uint24 newFee = (10000 - fee) * 100;
        (amountIn,amountOut,endLiquidity,tickCurrent) = AMethodContract.GetTokenInAndTokenOut(tokenIn,tokenOut,newFee,sqrtPricePresent,sqrtPriceTarget,liquidity);
    }

    // 获得Tick
    function GetTickLocal(uint160 SqrtPrice)external pure returns(int24){
       int24 ticks = TickMath.getTickAtSqrtRatio(SqrtPrice);
       return ticks;
    }

    // 获得下个tick的价格
    function GetNextTickSqrtPriceX96Local(address tokenIn,address tokenOut,int24 tick,int24 tickSpacing) external pure returns(uint160){
       uint160 tickSqrtPrice = AMethodContract.GetNextTickSqrtPriceX96(tokenIn,tokenOut,tick,tickSpacing);
       return tickSqrtPrice;
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

    //根据获得计算投入和价格
    function ExactOutputSingle(ContractCalculateIn memory _CalculateData)external view returns (ExactResult memory _ExactResult){
        uint24 curfee9975 = _CalculateData.Fee9975; // 9975类型
        int24 tick = TickMath.getTickAtSqrtRatio(_CalculateData.SqrtPrice);
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
        // amountIn = state.amountCalculated;
        // liquidity = state.liquidity;
        // afterTick = state.tick;
    }

    // 获取只在当前map的特定价格买入或者卖出完后的投入、得到、目标价格、tick、流动性
    function GetAreaAmountInAndOutStruct(PairData memory pairData,uint optype)external view returns (AmountInAndOutResult memory _arPair) {
        int24 tick = TickMath.getTickAtSqrtRatio(pairData.SqrtPrice);
        int24 tickSpacing = IPancakePairV3(pairData.Pair).tickSpacing();
        if (optype == 1){
            _arPair.tickSqrtPrice = AMethodContract.GetNextTickSqrtPriceX96(pairData.Stable,pairData.Token,tick,tickSpacing);
            (_arPair.amountIn,_arPair.amountOut,_arPair.endLiquidity,_arPair.tickCurrent) = this.GetAmountInAndOut(pairData.Stable, pairData.Token, pairData.Fee9975, pairData.SqrtPrice, _arPair.tickSqrtPrice, pairData.Liquidity);
        }else{
            _arPair.tickSqrtPrice = AMethodContract.GetNextTickSqrtPriceX96(pairData.Token,pairData.Stable,tick,tickSpacing);
            (_arPair.amountIn,_arPair.amountOut,_arPair.endLiquidity,_arPair.tickCurrent) = this.GetAmountInAndOut(pairData.Token, pairData.Stable, pairData.Fee9975, pairData.SqrtPrice, _arPair.tickSqrtPrice, pairData.Liquidity);
        }
        return _arPair;
    }

    struct BestY2{
        uint256 Pair1x2;
        uint256 Execy2;
        uint256 Pair2x4;
        uint160 Pair1SqrtPrice;
        uint128 Pair1Liquidity;
        int24 Pair1Tick;
        uint256 Pair1StableReserve;
        uint256 Pair1TokenReserve; 
        uint160 Pair2SqrtPrice;
        uint128 Pair2Liquidity;
        int24 Pair2Tick;
        uint256 Pair2StableReserve;
        uint256 Pair2TokenReserve;
        uint256 WbnbPrice;
        uint256 WbnbQuoDecimals;
        int256 MulNumber;
    }

    function GetBestY2V3(uint256 y2,BestY2 memory besty2,PairData memory pairData1,PairData memory pairData2)external returns(BestY2 memory _besty2){
        AmountInAndOutResult memory _arPair1 = this.GetAreaAmountInAndOutStruct(pairData1,1); // P2在Pair1买入
        AmountInAndOutResult memory _arPair2 = this.GetAreaAmountInAndOutStruct(pairData2,2); // P2在Pair2卖出
        uint256 minY2 = GetMin(uint256(y2), _arPair1.amountOut, _arPair2.amountIn);
        if (minY2 == y2){
            // 计算在Pair1 买入 y2 需要的投入
            ContractCalculateIn memory _CalculateData1 = ContractCalculateIn({TokenIn:pairData1.Stable,TokenOut:pairData1.Token,AmountIn:0,AmountOut:y2,Fee9975:pairData1.Fee9975,SqrtPrice:pairData1.SqrtPrice,Pair:pairData1.Pair});
            ExactResult memory _ExactResultPair1 = this.ExactOutputSingle(_CalculateData1);

            _besty2.Pair1SqrtPrice = besty2.Pair1SqrtPrice = _ExactResultPair1.SqrtPrice;
            _besty2.Pair1Liquidity = besty2.Pair1Liquidity = _ExactResultPair1.Liquidity;
            _besty2.Pair1Tick = besty2.Pair1Tick = _ExactResultPair1.Tick;

            // 计算在Pair2 卖出 y2 需要的得到
            ContractCalculateIn memory _CalculateData2 = ContractCalculateIn({TokenIn:pairData2.Token,TokenOut:pairData2.Stable,AmountIn:y2,AmountOut:0,Fee9975:pairData2.Fee9975,SqrtPrice:pairData2.SqrtPrice,Pair:pairData2.Pair});
            ExactResult memory _ExactResultPair2 = this.ExactInputSingle(_CalculateData2);

            _besty2.Pair2SqrtPrice = besty2.Pair2SqrtPrice = _ExactResultPair2.SqrtPrice;
            _besty2.Pair2Liquidity = besty2.Pair2Liquidity = _ExactResultPair2.Liquidity;
            _besty2.Pair2Tick = besty2.Pair2Tick = _ExactResultPair2.Tick;

            _besty2.Pair1x2 = besty2.Pair1x2 = _ExactResultPair1.Amount + besty2.Pair1x2;
            _besty2.Execy2 = besty2.Execy2 = minY2 + besty2.Execy2;
            _besty2.Pair2x4 = besty2.Pair2x4 = _ExactResultPair2.Amount + besty2.Pair2x4;
        }else{
            if (minY2 == _arPair1.amountOut){ // 最小值是Pair1的这个区间结果时，表示Pair1会跨map，那么在Pair1买入这个最小值，在Pair2卖出这个最小值，得到Pair1和Pair2的最新价格和流动性，用于转v2库存
                // 在Pair1买到的是最小值，所以价格和流动性就是Pair1上一步算出的结果
                pairData1.SqrtPrice = _arPair1.tickSqrtPrice;
                pairData1.Liquidity = _arPair1.endLiquidity;

                _besty2.Pair1SqrtPrice = besty2.Pair1SqrtPrice = _arPair1.tickSqrtPrice;
                _besty2.Pair1Liquidity = besty2.Pair1Liquidity = _arPair1.endLiquidity;
                _besty2.Pair1Tick = besty2.Pair1Tick = _arPair1.tickCurrent;

                // 在Pair2卖出这个最小值
                ContractCalculateIn memory _CalculateData = ContractCalculateIn({TokenIn:pairData2.Token,TokenOut:pairData2.Stable,AmountIn:minY2,AmountOut:0,Fee9975:pairData2.Fee9975,SqrtPrice:pairData2.SqrtPrice,Pair:pairData2.Pair});
                // (uint256 pair2TempAmountOut,uint160 pair2TempSqrtPriceAfter,uint128 pair2TempLiquidity,) = this.ExactInputSingle(_CalculateData);
                // pairData2.SqrtPrice = uint160(pair2TempSqrtPriceAfter);
                // pairData2.Liquidity = uint128(pair2TempLiquidity);
                ExactResult memory _ExactResultPair2 = this.ExactInputSingle(_CalculateData);
                pairData2.SqrtPrice = _ExactResultPair2.SqrtPrice;
                pairData2.Liquidity = _ExactResultPair2.Liquidity;
                
                _besty2.Pair2SqrtPrice = besty2.Pair2SqrtPrice = _ExactResultPair2.SqrtPrice;
                _besty2.Pair2Liquidity = besty2.Pair2Liquidity = _ExactResultPair2.Liquidity;
                _besty2.Pair2Tick = besty2.Pair2Tick = _ExactResultPair2.Tick;

                _besty2.Pair1x2 = besty2.Pair1x2 = _arPair1.amountIn + besty2.Pair1x2;
                _besty2.Execy2 = besty2.Execy2 = minY2 + besty2.Execy2;
                _besty2.Pair2x4 = besty2.Pair2x4 = _ExactResultPair2.Amount + besty2.Pair2x4;
            }else{ // 最小值是Pair2的这个区间结果时，表示Pair2会跨map，那么在Pair1不能买这么多，只能买入Pair2能卖出的这个最小数量，然后在Pair2卖出这个最小值，得到Pair1和Pair2的最新价格和流动性，用于转v2库存
                // 在Pair1买入这个最小值
                ContractCalculateIn memory _CalculateData = ContractCalculateIn({TokenIn:pairData1.Stable,TokenOut:pairData1.Token,AmountIn:0,AmountOut:minY2,Fee9975:pairData1.Fee9975,SqrtPrice:pairData1.SqrtPrice,Pair:pairData1.Pair});
                // (uint256 pair1TempAmountIn,uint160 pair1TempSqrtPriceAfter,uint128 pair1TempLiquidity,) = this.ExactOutputSingle(_CalculateData);
                // pairData1.SqrtPrice = uint160(pair1TempSqrtPriceAfter);
                // pairData1.Liquidity = uint128(pair1TempLiquidity);
                ExactResult memory _ExactResultPair1 = this.ExactOutputSingle(_CalculateData);
                pairData1.SqrtPrice = _ExactResultPair1.SqrtPrice;
                pairData1.Liquidity = _ExactResultPair1.Liquidity;

                _besty2.Pair1SqrtPrice = besty2.Pair1SqrtPrice = _ExactResultPair1.SqrtPrice;
                _besty2.Pair1Liquidity = besty2.Pair1Liquidity = _ExactResultPair1.Liquidity;
                _besty2.Pair1Tick = besty2.Pair1Tick = _ExactResultPair1.Tick;
               
                // 在Pair2卖出的是最小值，所以价格和流动性就是Pair2上一步算出的结果
                pairData2.SqrtPrice = _arPair2.tickSqrtPrice;
                pairData2.Liquidity = _arPair2.endLiquidity;

                _besty2.Pair2SqrtPrice = besty2.Pair2SqrtPrice = _arPair2.tickSqrtPrice;
                _besty2.Pair2Liquidity = besty2.Pair2Liquidity = _arPair2.endLiquidity;
                _besty2.Pair2Tick = besty2.Pair2Tick = _arPair2.tickCurrent;

                _besty2.Pair1x2 = besty2.Pair1x2 = _ExactResultPair1.Amount + besty2.Pair1x2;
                _besty2.Execy2 = besty2.Execy2 = minY2 + besty2.Execy2;
                _besty2.Pair2x4 = besty2.Pair2x4 = _arPair2.amountOut + besty2.Pair2x4;
            }
            uint256 newY2 = this.FlashLoan(pairData1,pairData2,besty2.WbnbPrice,besty2.WbnbQuoDecimals,besty2.MulNumber);
            if (newY2 > 0){
                _besty2 = this.GetBestY2V3(newY2,besty2,pairData1,pairData2);
            }
        }
    }

    function GetBestY2V2(uint256 y2,BestY2 memory besty2,PairData memory pairData1,PairData memory pairData2)external returns(BestY2 memory _besty2){
        if (pairData1.PairType == 3){
            AmountInAndOutResult memory _arPair1 = this.GetAreaAmountInAndOutStruct(pairData1,1);
            if (_arPair1.amountOut >= y2){
                // 计算在Pair1 买入 y2 需要的投入
                ContractCalculateIn memory _CalculateData = ContractCalculateIn({TokenIn:pairData1.Stable,TokenOut:pairData1.Token,AmountIn:0,AmountOut:y2,Fee9975:pairData1.Fee9975,SqrtPrice:pairData1.SqrtPrice,Pair:pairData1.Pair});
                ExactResult memory _ExactResultPair1 = this.ExactOutputSingle(_CalculateData);
                _besty2.Pair1SqrtPrice = besty2.Pair1SqrtPrice = _ExactResultPair1.SqrtPrice;
                _besty2.Pair1Liquidity = besty2.Pair1Liquidity = _ExactResultPair1.Liquidity;
                _besty2.Pair1Tick = besty2.Pair1Tick = _ExactResultPair1.Tick;

                // 在Pair2卖出 Pair1买到的Token，得到稳定币 p2*a2*y3/(10000*b2 + p2*y3)
                uint256 p2Pair2SellResultStableAmount = uint256(pairData2.Fee9975) * pairData2.StableReserve * y2 / (10000 * pairData2.TokenReserve + uint256(pairData2.Fee9975)*y2);
                _besty2.Pair2StableReserve = besty2.Pair2StableReserve = pairData2.StableReserve - p2Pair2SellResultStableAmount;
                _besty2.Pair2TokenReserve = besty2.Pair2TokenReserve = pairData2.TokenReserve + y2;

                _besty2.Pair1x2 = besty2.Pair1x2 += _ExactResultPair1.Amount;
                _besty2.Execy2 = besty2.Execy2 += y2;
                _besty2.Pair2x4 = besty2.Pair2x4 += p2Pair2SellResultStableAmount;
            }else{
                // Pair1买入这个值后的库存变化
                pairData1.SqrtPrice = _arPair1.tickSqrtPrice;
                pairData1.Liquidity = _arPair1.endLiquidity;

                _besty2.Pair1SqrtPrice = besty2.Pair1SqrtPrice = _arPair1.tickSqrtPrice;
                _besty2.Pair1Liquidity = besty2.Pair1Liquidity = _arPair1.endLiquidity;
                _besty2.Pair1Tick = besty2.Pair1Tick = _arPair1.tickCurrent;

                // 在Pair2卖出 Pair1买到的Token，得到稳定币 以及库存变化情况 // p2*a2*y3/(10000*b2 + p2*y3)
                uint256 p2Pair2SellResultStableAmount = uint256(pairData2.Fee9975) * pairData2.StableReserve * _arPair1.amountOut / (10000 * pairData2.TokenReserve + uint256(pairData2.Fee9975)*_arPair1.amountOut);
                pairData2.StableReserve -= p2Pair2SellResultStableAmount;
                pairData2.TokenReserve += _arPair1.amountOut;

                _besty2.Pair2StableReserve = besty2.Pair2StableReserve = pairData2.StableReserve;
                _besty2.Pair2TokenReserve = besty2.Pair2TokenReserve = pairData2.TokenReserve;

                _besty2.Pair1x2 = besty2.Pair1x2 += _arPair1.amountIn;
                _besty2.Execy2 = besty2.Execy2 += _arPair1.amountOut;
                _besty2.Pair2x4 = besty2.Pair2x4 += p2Pair2SellResultStableAmount;

                uint256 newY2 = this.FlashLoan(pairData1,pairData2,besty2.WbnbPrice,besty2.WbnbQuoDecimals,besty2.MulNumber);
                if (newY2 > 0){
                    _besty2 = this.GetBestY2V2(newY2,besty2,pairData1,pairData2);
                }
            }
        }else{
            AmountInAndOutResult memory _arPair2 = this.GetAreaAmountInAndOutStruct(pairData2,2);
            if (_arPair2.amountIn >= y2){
                // 在Pair1 买入 Pair2在当前map能卖出的全部Token，算出投入的稳定币 不需要再管库存变化情况
                uint256 p2buyTokenUseStable = 10000 * y2 * pairData1.StableReserve / (pairData1.Fee9975 * (pairData1.TokenReserve - y2));
                _besty2.Pair1StableReserve = pairData1.StableReserve + p2buyTokenUseStable;
                _besty2.Pair1TokenReserve = pairData1.TokenReserve - y2;

                // 计算在Pair2 卖出 y2 需要的得到
                ContractCalculateIn memory _CalculateData2 = ContractCalculateIn({TokenIn:pairData2.Token,TokenOut:pairData2.Stable,AmountIn:y2,AmountOut:0,Fee9975:pairData2.Fee9975,SqrtPrice:pairData2.SqrtPrice,Pair:pairData2.Pair});
                // (uint256 pair2TempAmountOut,,,) = this.ExactInputSingle(_CalculateData2);
                ExactResult memory _ExactResultPair2 = this.ExactInputSingle(_CalculateData2);

                _besty2.Pair2SqrtPrice = besty2.Pair2SqrtPrice = _ExactResultPair2.SqrtPrice;
                _besty2.Pair2Liquidity = besty2.Pair2Liquidity = _ExactResultPair2.Liquidity;
                _besty2.Pair2Tick = besty2.Pair2Tick = _ExactResultPair2.Tick;

                _besty2.Pair1x2 = besty2.Pair1x2 += p2buyTokenUseStable;
                _besty2.Execy2 = besty2.Execy2 += y2;
                _besty2.Pair2x4 = besty2.Pair2x4 += _ExactResultPair2.Amount;
            }else{
                // Pair2卖出这个值后的库存变化
                pairData2.SqrtPrice = _arPair2.tickSqrtPrice;
                pairData2.Liquidity = _arPair2.endLiquidity;

                _besty2.Pair2SqrtPrice = besty2.Pair2SqrtPrice = _arPair2.tickSqrtPrice;
                _besty2.Pair2Liquidity = besty2.Pair2Liquidity = _arPair2.endLiquidity;
                _besty2.Pair2Tick = besty2.Pair2Tick = _arPair2.tickCurrent;

                // 在Pair1 买入 Pair2在当前map能卖出的全部Token，算出需要投入的稳定币 以及库存变化情况 10000*token*stableReserveBeofre / (fee*(tokenReserveBefore-token))
                uint256 p2Pair1BuyTokenUseStable = 10000 * _arPair2.amountIn * pairData1.StableReserve / (pairData1.Fee9975 * (pairData1.TokenReserve - _arPair2.amountIn));
                pairData1.StableReserve += p2Pair1BuyTokenUseStable;
                pairData1.TokenReserve -= _arPair2.amountIn;

                // Pair1 V2 库存变化
                _besty2.Pair1StableReserve = besty2.Pair1StableReserve = pairData1.StableReserve;
                _besty2.Pair1TokenReserve = besty2.Pair1TokenReserve = pairData1.TokenReserve;

                _besty2.Pair1x2 = besty2.Pair1x2 += p2Pair1BuyTokenUseStable;
                _besty2.Execy2 = besty2.Execy2 += _arPair2.amountIn;
                _besty2.Pair2x4 = besty2.Pair2x4 += _arPair2.amountOut;

                uint256 newY2 = this.FlashLoan(pairData1,pairData2,besty2.WbnbPrice,besty2.WbnbQuoDecimals,besty2.MulNumber);
                if (newY2 > 0){
                    _besty2 = this.GetBestY2V2(newY2,besty2,pairData1,pairData2);
                }
            }
        }
    }

    function FlashLoan(PairData memory pairData1,PairData memory pairData2,uint256 bnbPrice,uint256 bnbPriceQuo,int256 MulNumber)external view returns (uint256 y2){
        // 执行闪电贷公式计算新的y2
        y2 = 0;
        int256 a1;
        int256 b1;
        int256 a2;
        int256 b2;
        int256 p1 = pairData1.Fee9975;
        int256 p2 = pairData2.Fee9975;

        if (pairData1.PairType == 2){
            a1 = int256(pairData1.StableReserve);
            b1 = int256(pairData1.TokenReserve);
            if (pairData1.Stable != pairData2.Stable && pairData1.Stable == Wbnb){
                a1 = a1 * int256(bnbPrice) / int256(bnbPriceQuo);
            }
        }else{
            // Pair1转成v2的库存
            if (pairData1.Token > pairData1.Stable){ //stable小于token, 稳定币在0号位 即location = 0
                a1 = int256(pairData1.Liquidity) * int256(X96) / int256(pairData1.SqrtPrice);
                b1 = int256(pairData1.Liquidity) * int256(pairData1.SqrtPrice) / int256(X96);
            }else{
                a1 = int256(pairData1.Liquidity) * int256(pairData1.SqrtPrice) / int256(X96);
                b1 = int256(pairData1.Liquidity) * int256(X96) / int256(pairData1.SqrtPrice);
            }
            if (pairData1.Stable != pairData2.Stable && pairData1.Stable == Wbnb){
                a1 = a1 * int256(bnbPrice) / int256(bnbPriceQuo);
            }
        }
        
        if (pairData2.PairType == 2){
            a2 = int256(pairData2.StableReserve);
            b2 = int256(pairData2.TokenReserve);
            if (pairData1.Stable != pairData2.Stable && pairData2.Stable == Wbnb){
                a2 = a2 * int256(bnbPrice) / int256(bnbPriceQuo);
            }
        }else{
            // Pair2转成v2库存
            if (pairData2.Token > pairData2.Stable){ //stable小于token, 稳定币在0号位 即location = 0
                a2 = int256(pairData2.Liquidity) * int256(X96) / int256(pairData2.SqrtPrice);
                b2 = int256(pairData2.Liquidity) * int256(pairData2.SqrtPrice) / int256(X96);
            }else{
                a2 = int256(pairData2.Liquidity) * int256(pairData2.SqrtPrice) / int256(X96);
                b2 = int256(pairData2.Liquidity) * int256(X96) / int256(pairData2.SqrtPrice);
            }
            if (pairData1.Stable != pairData2.Stable && pairData2.Stable == Wbnb){
                a2 = a2 * int256(bnbPrice) / int256(bnbPriceQuo);
            }
        }
        
        // int256 A = (10000*a1*b1*p2**2 - 10000*a2*b2*p1*p2);
        // int256 B = (20000*a2*b1*b2*p1 + 200000000*a1*b1*b2)*p2;
        // int256 C = -10000*a2*b1**2*b2*p1*p2 + 1000000000000*a1*b1*b2**2;

        // A = (10000*a1_1*b1_1*p2^2 - 10000*a2_1*b2_1*p1*p2)
        int256 A = (MulNumber*a1*p2*p2/b2 - MulNumber*a2*p1*p2/b1);
        // B = (20000*a2_1*b1_1*b2_1*p1 + 200000000*a1_1*b1_1*b2_1) * p2
        int256 B = MulNumber*(2*a2*p1 + 20000*a1)*p2;
        // C = -10000*a2_1*b1_1^2*b2_1*p1*p2 + 1000000000000*a1_1*b1_1*b2_1^2
        int256 C = MulNumber*(-a2*b1*p1*p2 + 100000000*a1*b2);
        
        if (A != 0){
            int256 temp = B**2-4*A*C;
            if (temp > 0){
                int256 tmepSqrt = Sqrt(temp);
                int256 tempy2 = (-B + tmepSqrt)/(2*A);
                if (tempy2 > 0){
                    y2 = uint256(tempy2);
                }
            }
        }
    }

    function Sqrt(int256 x) internal pure returns (int256) {
        if (x == 0) {
            return 0;
        }
        int256 z = (x + 1) / 2;
        int256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return z;
    }

    function GetMin(uint256 a,uint256 b,uint256 c) internal pure returns (uint256) {
        return a < b && a < c ? a : (b < c ? b : c);
    }
}
