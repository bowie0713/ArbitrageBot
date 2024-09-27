// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Need to deposit ETH to WETH in order to transact on Uniswap V3 Router
// Refer to this: https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code
// And this: https://etherscan.io/tx/0xedfd6adf8c7b062927beacab9634c83566fcae79aee044a2eec68dd34ad853d8
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
// set up Uniswap Router to 
interface ISwapRouter {
    struct ExactInputSingleParams {
       address tokenIn;
       address tokenOut;
       uint24 fee;
       address recipient;
       uint256 deadline;
       uint256 amountIn;
       uint256 amountOutMinimum;
       uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params)
       external
       payable
       returns (uint256 amountOut);
}

interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
    // i: index for the value to send
    // j: index for the value to receive
    // dx: Amount of i being exchanged
    // min_dy: Minimum amount of j received 
    // Refer to: https://curve.readthedocs.io/exchange-pools.html
    function get_dy(int128 i, int128 j, uint128 _dx) external view returns (uint256);
}
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pair);
}



contract Arbitrage{
    //using SafeERC20 for IERC20;

    // ISwapRouter public immutable uniswapRouter;
    // ICurvePool public immutable curvePool;
    IWETH private constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // Uniswap

    address constant SWAP_ROUTER_02 = 0xE592427A0AEce92De3Edee1F18E0157C05861564; 
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant curvepoolAddress = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;

    function depositWETH() external payable{
        WETH.deposit{value: msg.value}();
        WETH.transfer(msg.sender, WETH.balanceOf(address(this)));
    }
    // receive ETH from WETH's withdraw function
    receive() external payable {}
    function withdrawWETH(uint256 amount) external{
        address payable sender = msg.sender;

        if (amount != 0) {
        // Taking tokens from a wallet require allowance, look up https://eips.ethereum.org/EIPS/eip-20#methods, especially the paragraphs on transferFrom() and approve()
        require(WETH.allowance(msg.sender, address(this)) >= amount, "insufficient allowance");
        WETH.transferFrom(msg.sender, address(this), amount);
        WETH.withdraw(amount);
        sender.transfer(address(this).balance);}
    }

    function swapExactInputSingleHop (address tokenIn, address tokenOut, uint256 amountIn, uint256 minETHamountout)
    internal returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(SWAP_ROUTER_02), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minETHamountout,
            sqrtPriceLimitX96: 0
        });
        amountOut = ISwapRouter.exactInputSingle(params);
    }
    function getTokenAmountOnUniswap(uint256 amountIn) external view returns(uint256 amountOut){
        address addressPool = IUniswapV3Factory.getPool(address(USDC), address(WETH), 1000);
        IUniswapV3Pool pool = IUniswapV3Pool(addressPool);
        // Get the current sqrtPriceX96 from Uniswap V3 pool's slot0
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        // Calculate the price of ETH in USDC based on sqrtPriceX96
        priceOut = (uint256(sqrtPriceX96)^2) / (1 << 192); // (1 << 192) refers to shifting 1 by 192 bits = 1*(2^(192))
        amountOut = priceOut * amountIn;
    } 
    function buyETHonUniswap(uint256 amountIn) external returns(uint256 amountOut){
        require(USDC.balanceOf(address(this)) >= amountIn, "USDC Balance Not Enough");
        amountOut = swapExactInputSingleHop(address(WETH), address(USDC), 1000, 0);
    }
    function sellETHonUniswap(uint256 amountIn) external returns(uint256 amountOut){
        require(WETH.balanceOf(address(this)) >= amountIn, "WETH Balance Not Enough");
        amountOut = swapExactInputSingleHop(address(USDC), address(WETH), 1000, 0);
    }
    // Curve 

    // Found it on : https://curve.fi/#/ethereum/pools/factory-tricrypto-3/deposit -> TricyptoUSDC
    // run the Read Contract on Etherscan: https://etherscan.io/address/0x7f86bf177dd4f3494b841a37e810a34dd56c829b#readContract
    // USDC: 0, WBTC:1 (ignore), WETH: 2 --> index
    function buyEthOnCurve(uint256 usdcAmountIn, uint256 minEthAmount) public {
        // Swap USDC for ETH, assuming USDC is 0 and ETH is 1
        require(USDC.balanceOF(address(this)) >= usdcAmountIn, "USDC Balance Not Enough");
        IERC20(address(USDC)).approve(address(curvepoolAddress), usdcAmountIn);
        curvePool.exchange(0, 2, usdcAmountIn, 1);
    }
    function sellEthonCurve(uint256 ethAmountIn, uint256 minUsdcAmount) public {
        require(WETH.balanceOf(address(this)) >= ethAmountIn, "WETH Balance Not Enough");
        IERC(address(WETH)).approve(address(curvepoolAddress), minUsdcAmount);
        curvePool.exchange(2, 0, ethAmountIn, minUsdcAmount);
        
    }
    function getTokenAmountonCurve(uint256 usdcamount) public view returns (uint256){
        return curvepoolAddress.get_dy(0, 2, usdcamount); // same as above
   }
    // Actual Arbitrage Function Execution
    function exchangeArbitrage(uint256 usdcAmount) external returns (uint256 profit){
        
        uint256 allowance = IERC20(address(USDC).allowance(msg.sender, address(this)));
        uint256 balance = IERC20(address(USDC).balanceOf(msg.sender));

        require(allowance >= usdcAmount, "Allowance too low");
        require(balance >= usdcAmount, "Insufficient balance");

        uint256 amountOutUSDC;
        uint256 amountOutETH;
        
        uint256 ETHamountOnUniswap = this.getTokenAmountOnUniswap(usdcamount);
        uint256 ETHamountOnCurve = this.getTokenAmountonCurve(usdcAmount);

        if(ETHamountOnUniswap > ETHamountOnCurve){
            amountOutETH = this.buyETHonUniswap(usdcAmount);
            amountOutUSDC = this.sellEthonCurve(amountOutETH, 0);
        } else{
            amountOutETH = this.buyEthonCurve(usdcAmount, 0);
            amountOutUSDC = this.sellETHonUniswap(amountOutETH);
        }
        require(amountOutUSDC - usdcAmount >= 0, "Arbitrage not Sucessful");
        profit = amountOutUSDC - usdcAmount;
        
        
        
   }




}
// Uniswap router address: 0xE592427A0AEce92De3Edee1F18E0157C05861564
// Curve router address: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7
// Both are on Ethereum Mainnet
