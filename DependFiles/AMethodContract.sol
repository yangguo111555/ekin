// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity  >=0.7.0 <0.8.0;
pragma abicoder v2;
import './LowGasSafeMath.sol';
import './SafeCast.sol';
import './FullMath.sol';
import './UnsafeMath.sol';
import './FixedPoint96.sol';
import './TickMath.sol';
import './SqrtPriceMath.sol';

interface IPancakePairV3{
    function liquidity() external view returns (uint128);
    function tickSpacing() external view returns (int24);
    function slot0() external view returns (uint160 sqrtPriceX96,int24 tick,uint16 observationIndex,uint16 observationCardinality,uint16 observationCardinalityNext,uint32 feeProtocol,bool unlocked);
    function ticks(int24 tick)external view returns (uint128 liquidityGross,int128 liquidityNet,uint256 feeGrowthOutside0X128,uint256 feeGrowthOutside1X128,int56 tickCumulativeOutside,uint160 secondsPerLiquidityOutsideX128,uint32 secondsOutside,bool initialized);
    function swap(address recipient,bool zeroForOne,int256 amountIn,uint160 sqrtPriceLimitX96,bytes calldata data) external;
}
interface IPancakeFactory{
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function getPool(address tokenA,address tokenB,uint24 fee) external view returns (address pool);
}
library AMethodContract{
    event Log(uint160);
    // event Log(string,int24);
    event Log(uint256);
    event Log(int24);
    // event Log(address);
    // event Log(string message, uint index, uint128 liquidity, int24 tickCurrent);
    // event Log(string strA, int24 tickA, string strB, int24 tickB);
    event Log(uint256 amountOut,uint160 sqrtPriceX96After);
    struct TickData{
        int24 TickCurrent;                     //当前tick
        int24 TickStart;                       //起始tick
        int24 TickEnd;                         //结束tick
        uint128 Liquidity;
        uint160 SqrtPriceX96;                  //当前tick对应的价格                 
        int24 TickSpacing;                   
        uint128 LiquidityGross;                 
        int128 LiquidityNet;                   
        uint256 FeeGrowthOutside0X128;          
        uint256 FeeGrowthOutside1X128;          
        int56 TickCumulativeOutside;          
        uint160 SecondsPerLiquidityOutsideX128; 
        uint32 SecondsOutside;                
        bool Initialized;                   
    }
    struct TickUpDown{
        int24 tick_down;
        int24 tick_up;
    }
    // function getAmount0Delta( uint160 sqrtRatioAX96,uint160 sqrtRatioBX96,uint128 liquidity,bool roundUp) external pure returns (uint256 amount0){
    //     return SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp);
    // }

    // function getAmount1Delta(uint160 sqrtRatioAX96,uint160 sqrtRatioBX96,uint128 liquidity,bool roundUp) external pure returns (uint256 amount1) {
    //     return SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp);
    // }
    // 计算两个价格之间的总流动性L
    function GetLiquidityBetweenTowPrices(address pair,uint160 sqrtPriceStartX96,uint160 sqrtPriceEndX96,uint128 liquidity)internal view returns (TickData[] memory) {
        int24 tickSpacing = IPancakePairV3(pair).tickSpacing();
        int24 tickA = TickMath.getTickAtSqrtRatio(sqrtPriceStartX96);
        int24 tickB = TickMath.getTickAtSqrtRatio(sqrtPriceEndX96);
        if(tickA > tickB){ //交易方向<------
            require(tickB > TickMath.MIN_TICK, 'TLM');
        }else{//交易方向------>
            require(tickB < TickMath.MAX_TICK, 'TUM');
        }
        TickUpDown memory tickStart;
        TickUpDown memory tickEnd;
        if (tickA < 0){
            if (tickA < tickB && tickA % tickSpacing == 0){//--------->
                tickStart.tick_down = tickA / tickSpacing * tickSpacing;
                tickStart.tick_up = (tickA / tickSpacing + 1) * tickSpacing;
            }else{//<---------
                tickStart.tick_down = (tickA / tickSpacing -1) * tickSpacing;
                tickStart.tick_up = (tickA / tickSpacing) * tickSpacing;
            }
	    }else{
            if (tickA > tickB && tickA % tickSpacing == 0){//<---------
                tickStart.tick_down = (tickA / tickSpacing -1) * tickSpacing;
                tickStart.tick_up = tickA / tickSpacing * tickSpacing;
            }else{//--------->
                tickStart.tick_down = tickA / tickSpacing * tickSpacing;
                tickStart.tick_up = (tickA / tickSpacing + 1) * tickSpacing;
            }
        }
        if (tickB < 0) {
            if (tickA < tickB && tickB % tickSpacing == 0){//--------->
                tickEnd.tick_down = tickB / tickSpacing * tickSpacing;
                tickEnd.tick_up = (tickB / tickSpacing +1)* tickSpacing;
            }else{
                tickEnd.tick_down = (tickB / tickSpacing - 1) * tickSpacing;
                tickEnd.tick_up = tickB / tickSpacing * tickSpacing;
            }
        }else{
            if (tickA > tickB && tickB % tickSpacing == 0){//<---------
                tickEnd.tick_down = (tickB / tickSpacing - 1)* tickSpacing;
                tickEnd.tick_up = tickB / tickSpacing  * tickSpacing;
            }else{
                tickEnd.tick_down = tickB / tickSpacing * tickSpacing;
                tickEnd.tick_up = (tickB / tickSpacing + 1) * tickSpacing;
            }
        }
        int24 tickStartA;
        int24 tickEndB;
        if (tickA > tickB){//交易方向<------
            tickStartA = tickStart.tick_up;
            tickEndB = tickEnd.tick_down;
        }else{//交易方向------>
            tickStartA = tickStart.tick_down;
            tickEndB = tickEnd.tick_up;
        }

        // emit Log("A",tickA,"B",tickB);
        // emit Log("tickSpacing",tickSpacing);
        // 确保 tickA 小于 tickB
        if (tickA > tickB) { //交易方向<------
            (tickStartA,tickEndB) = (tickEndB, tickStartA);
        } else { //交易方向------>
            (tickStartA, tickEndB) = (tickStartA, tickEndB);
        }
        TickData[] memory tickArr = new TickData[](uint256((tickEndB - tickStartA) / tickSpacing + 1));
        uint256 index = 0;
        // 遍历并累积 tick 范围内的流动性数据
        for (int24 tick = tickStartA; tick <= tickEndB; tick += tickSpacing) {
            if(tick > (tickA>tickB?tickB:tickA) && tick < (tickA>tickB?tickA:tickB)){
                TickData memory td;
                (td.LiquidityGross,td.LiquidityNet,td.FeeGrowthOutside0X128,td.FeeGrowthOutside1X128,td.TickCumulativeOutside,td.SecondsPerLiquidityOutsideX128,td.SecondsOutside,td.Initialized) = IPancakePairV3(pair).ticks(tick);
                td.SqrtPriceX96 =  TickMath.getSqrtRatioAtTick(tick);
                td.TickCurrent = tick;
                tickArr[index] = td;
                index++;
            }
        }
        // 过滤未使用的数组部分
        if (index < uint256((tickEndB - tickStartA) / tickSpacing + 1)) {
            assembly {
                mstore(tickArr, index)
            }
        }
        uint i;
	    if (tickA > tickB) { //交易方向<------降序
            tickArr = sort(tickArr,false);
            for (i = 0; i < tickArr.length; i++) {
                if (i == 0) {
                    tickArr[i].Liquidity = liquidity;
                } else {
                    tickArr[i].Liquidity = tickArr[i-1].Liquidity + uint128(-tickArr[i].LiquidityNet);
                }
                // emit Log("Liquidity:::", i, tickArr[i].Liquidity, tickArr[i].TickCurrent);
		    }
        } else { //交易方向------>升序
            tickArr = sort(tickArr,true);
            for (i = 0; i < tickArr.length; i++) {
                if (i == 0) {
                    tickArr[i].Liquidity = liquidity;
                } else {
                    tickArr[i].Liquidity = tickArr[i-1].Liquidity + uint128(tickArr[i].LiquidityNet);
                }
                // emit Log("Liquidity:::", i, tickArr[i].Liquidity, tickArr[i].TickCurrent);
            }
        }
        return tickArr;
    }
    //获取两个价格之间的投入和获得
    function GetTokenInAndTokenOut(address tokenIn,address tokenOut,uint24 fee,uint160 sqrtPriceStartX96,uint160 sqrtPriceEndX96,uint128 liquidity) internal view returns (uint256 amountIn, uint256 amountOut,uint128 endLiquidity,int24 tickCurrent) {
        address pair = IPancakeFactory(address(0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865)).getPool(tokenIn,tokenOut,fee);
        TickData[] memory tickArr = GetLiquidityBetweenTowPrices(pair,sqrtPriceStartX96,sqrtPriceEndX96,liquidity);
        bool zeroForOne = sqrtPriceStartX96>= sqrtPriceEndX96;
        uint i;
        tickCurrent = TickMath.getTickAtSqrtRatio(sqrtPriceEndX96);
        if (zeroForOne){ //交易方向<------
            if (tickArr.length == 0){
                amountIn += SqrtPriceMath.getAmount0Delta(sqrtPriceEndX96, sqrtPriceStartX96, liquidity, true);
                amountOut += SqrtPriceMath.getAmount1Delta(sqrtPriceEndX96, sqrtPriceStartX96,liquidity, false);
                endLiquidity = liquidity;
            }else{
                for (i = 0; i < tickArr.length; i++) {
                    uint160 strartPrice;
                    uint160 endPrice;
                    if (tickArr.length == 1){
                        strartPrice = sqrtPriceStartX96;
                        endPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        amountIn += SqrtPriceMath.getAmount0Delta(endPrice, strartPrice, liquidity, true);
                        amountOut += SqrtPriceMath.getAmount1Delta(endPrice, strartPrice, liquidity, false);

                        strartPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        endPrice = sqrtPriceEndX96;
                        amountIn += SqrtPriceMath.getAmount0Delta(endPrice, strartPrice, tickArr[i].Liquidity, true);
                        amountOut += SqrtPriceMath.getAmount1Delta(endPrice, strartPrice, tickArr[i].Liquidity, false);
                        endLiquidity = tickArr[i].Liquidity;
                    }else if (i == 0){
                        strartPrice = sqrtPriceStartX96;
                        endPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        amountIn += SqrtPriceMath.getAmount0Delta(endPrice, strartPrice, liquidity, true);
                        amountOut += SqrtPriceMath.getAmount1Delta(endPrice, strartPrice, liquidity, false);
                        endLiquidity = tickArr[i].Liquidity;
                    } else if (i == tickArr.length-1) {
                        strartPrice = TickMath.getSqrtRatioAtTick(tickArr[i-1].TickCurrent);
                        endPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        amountIn += SqrtPriceMath.getAmount0Delta(endPrice, strartPrice, tickArr[i-1].Liquidity, true);
                        amountOut += SqrtPriceMath.getAmount1Delta(endPrice, strartPrice, tickArr[i-1].Liquidity, false);

                        strartPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        endPrice = sqrtPriceEndX96;
                        amountIn += SqrtPriceMath.getAmount0Delta(endPrice, strartPrice, tickArr[i].Liquidity, true);
                        amountOut += SqrtPriceMath.getAmount1Delta(endPrice, strartPrice, tickArr[i].Liquidity, false);
                        endLiquidity = tickArr[i].Liquidity;
                    } else {
                        strartPrice = TickMath.getSqrtRatioAtTick(tickArr[i-1].TickCurrent);
                        endPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        amountIn += SqrtPriceMath.getAmount0Delta(endPrice, strartPrice, tickArr[i-1].Liquidity, true);
                        amountOut += SqrtPriceMath.getAmount1Delta(endPrice, strartPrice, tickArr[i-1].Liquidity, false);
                        endLiquidity = tickArr[i].Liquidity;
                    }
                }
            }
        }else{//交易方向------->
            if (tickArr.length == 0){
                amountIn += SqrtPriceMath.getAmount1Delta(sqrtPriceStartX96, sqrtPriceEndX96, liquidity, true);
                amountOut += SqrtPriceMath.getAmount0Delta(sqrtPriceStartX96, sqrtPriceEndX96, liquidity, false);
                endLiquidity = liquidity;
            }else{
                for (i = 0; i < tickArr.length; i++) {
                    uint160 strartPrice;
                    uint160 endPrice;
                     if (tickArr.length == 1){
                        strartPrice = sqrtPriceStartX96;
                        endPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        amountIn += SqrtPriceMath.getAmount1Delta(strartPrice, endPrice, liquidity, true);
                        amountOut += SqrtPriceMath.getAmount0Delta(strartPrice, endPrice, liquidity, false);

                        strartPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        endPrice = sqrtPriceEndX96;
                        amountIn += SqrtPriceMath.getAmount1Delta(strartPrice, endPrice, tickArr[i].Liquidity, true);
                        amountOut += SqrtPriceMath.getAmount0Delta(strartPrice, endPrice, tickArr[i].Liquidity, false);
                        endLiquidity = tickArr[i].Liquidity;
                    }else if (i == 0){
                        strartPrice = sqrtPriceStartX96;
                        endPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        amountIn += SqrtPriceMath.getAmount1Delta(strartPrice, endPrice, liquidity, true);
                        amountOut += SqrtPriceMath.getAmount0Delta(strartPrice, endPrice, liquidity, false);
                        endLiquidity = liquidity;
                    } else if (i == tickArr.length-1) {
                        strartPrice = TickMath.getSqrtRatioAtTick(tickArr[i-1].TickCurrent);
                        endPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        amountIn += SqrtPriceMath.getAmount1Delta(strartPrice, endPrice, tickArr[i-1].Liquidity, true);
                        amountOut += SqrtPriceMath.getAmount0Delta(strartPrice, endPrice, tickArr[i-1].Liquidity, false);

                        strartPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        endPrice = sqrtPriceEndX96;
                        amountIn += SqrtPriceMath.getAmount1Delta(strartPrice, endPrice, tickArr[i].Liquidity, true);
                        amountOut += SqrtPriceMath.getAmount0Delta(strartPrice, endPrice, tickArr[i].Liquidity, false);
                        endLiquidity = tickArr[i].Liquidity;
                    } else {
                        strartPrice = TickMath.getSqrtRatioAtTick(tickArr[i-1].TickCurrent);
                        endPrice = TickMath.getSqrtRatioAtTick(tickArr[i].TickCurrent);
                        amountIn += SqrtPriceMath.getAmount1Delta(strartPrice, endPrice, tickArr[i-1].Liquidity, true);
                        amountOut += SqrtPriceMath.getAmount0Delta(strartPrice, endPrice, tickArr[i-1].Liquidity, false);
                        endLiquidity = tickArr[i-1].Liquidity;
                    }
                }
            }
        }
        amountIn = FullMath.mulDivRoundingUp(amountIn, fee, 1e6 - fee) + amountIn;
        // emit Log(amountIn);
        // emit Log(amountOut);
        // emit Log(endLiquidity);
        return (amountIn,amountOut,endLiquidity,tickCurrent);
    }

    // 获取同交易方向map的下一个价格
    function GetNextTickSqrtPriceX96(address tokenIn,address tokenOut,int24 tickCurrent,int24 tickSpacing) internal pure returns (uint160 sqrtPriceX96After) {
        int24 tickNum = tickCurrent/tickSpacing;
        TickUpDown memory tickStart;
         if (tickCurrent < 0){
            if (tokenIn > tokenOut && tickCurrent % tickSpacing == 0){//--------->
                  tickStart.tick_down = tickNum * tickSpacing;
                tickStart.tick_up = (tickNum + 1) * tickSpacing;
            }else{//<---------
                tickStart.tick_down = (tickNum -1) * tickSpacing;
                tickStart.tick_up = tickNum * tickSpacing;
            }
	    }else{
            if (tokenIn < tokenOut && tickCurrent % tickSpacing == 0){//<---------
                tickStart.tick_down = (tickNum -1) * tickSpacing;
                tickStart.tick_up = tickNum * tickSpacing;
            }else{//--------->
                tickStart.tick_down = tickNum * tickSpacing;
                tickStart.tick_up = (tickNum + 1) * tickSpacing;
            }
        }
        if (tokenIn < tokenOut) { //<------
            sqrtPriceX96After = TickMath.getSqrtRatioAtTick(tickStart.tick_down);
        }else{
            sqrtPriceX96After = TickMath.getSqrtRatioAtTick(tickStart.tick_up);
        }
    }
    //排序upOrDrop true为升false为降
    function sort(TickData[] memory data,bool upOrDrop) internal pure returns (TickData[] memory) {
        // Simple Bubble Sort implementation
        uint length = data.length;
        for (uint i = 0; i < length; i++) {
            for (uint j = 0; j < length - 1; j++) {
                if (upOrDrop?data[j].TickCurrent > data[j + 1].TickCurrent:data[j].TickCurrent < data[j + 1].TickCurrent) {
                    TickData memory temp = data[j];
                    data[j] = data[j + 1];
                    data[j + 1] = temp;
                }
            }
        }
        return data;
    }
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
    }
}