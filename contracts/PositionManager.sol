// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// ─────────────────────────────────────────────────────────────────
//  Pharaoh CL Interfaces  (Uniswap V3 compatible)
// ─────────────────────────────────────────────────────────────────

interface IUniswapV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function tickSpacing() external view returns (int24);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    function burn(uint256 tokenId) external payable;

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

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

// WAVAX interface for wrapping native AVAX
interface IWAVAX {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address guy, uint256 wad) external returns (bool);
    function transfer(address dst, uint256 wad) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

// ─────────────────────────────────────────────────────────────────
//  TickMath helper — computes sqrt price for a given tick
//  (abridged, integer-only version sufficient for range calc)
// ─────────────────────────────────────────────────────────────────

library TickMath {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;

    // Returns the sqrt ratio as a Q64.96 for a given tick.
    // Full implementation mirrors Uniswap V3's TickMath.getSqrtRatioAtTick.
    function getSqrtRatioAtTick(int24 tick)
        internal
        pure
        returns (uint160 sqrtPriceX96)
    {
        uint256 absTick = tick < 0
            ? uint256(-int256(tick))
            : uint256(int256(tick));
        require(absTick <= uint256(int256(MAX_TICK)), "T");

        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0)  ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0)  ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0)  ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
}

// ─────────────────────────────────────────────────────────────────
//  LiquidityAmounts — compute amounts from liquidity & sqrt prices
// ─────────────────────────────────────────────────────────────────

library LiquidityAmounts {
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return
            (uint256(liquidity) *
                uint256(sqrtRatioBX96 - sqrtRatioAX96) *
                (2**96)) /
            uint256(sqrtRatioBX96) /
            uint256(sqrtRatioAX96);
    }

    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return
            (uint256(liquidity) * uint256(sqrtRatioBX96 - sqrtRatioAX96)) /
            (2**96);
    }

    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = (uint256(sqrtRatioAX96) *
            uint256(sqrtRatioBX96)) / (2**96);
        return
            uint128(
                (amount0 * intermediate) /
                    uint256(sqrtRatioBX96 - sqrtRatioAX96)
            );
    }

    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return
            uint128(
                (uint256(amount1) * (2**96)) /
                    uint256(sqrtRatioBX96 - sqrtRatioAX96)
            );
    }

    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96)
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount0
            );
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(
                sqrtRatioX96,
                sqrtRatioBX96,
                amount0
            );
            uint128 liquidity1 = getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioX96,
                amount1
            );
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount1
            );
        }
    }
}

// ─────────────────────────────────────────────────────────────────
//
//  PharaohCLManager
//
//  Manages a single AVAX/USDC concentrated liquidity position on
//  Pharaoh Exchange (Avalanche C-Chain).
//
//  • Accepts USDC deposits and swaps ~50 % to WAVAX to seed the
//    position symmetrically around the current price.
//  • All deposits add to the single NFT position.
//  • rebalance() closes the position and reopens it centred on the
//    current price when the position has gone out of range.
//  • claimFees(recipient) collects pending fees and forwards them.
//
// ─────────────────────────────────────────────────────────────────

/**
 * @title  PharaohCLManager
 * @notice Single-position concentrated liquidity manager for the
 *         AVAX/USDC pool on Pharaoh Exchange (Avalanche C-Chain).
 *
 * Key addresses (Avalanche Mainnet):
 *   WAVAX  : 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7
 *   USDC   : 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6e
 *   NPM    : 0xAAA78E8C4241990B4ce159E105dA08129345946A
 *   Factory: 0xAAA32926fcE6bE95ea2c51cB4Fcb60836D320C42
 *   Router : 0xAAAE99091Fbb28D400029052821653C1C752483B
 *
 * Pool fee tier : 3000 (0.30 %)  — adjust if using 500 / 10000
 */
contract PharaohCLManager is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    // ─── Immutables ───────────────────────────────────────────────

    /// @notice Wrapped AVAX token
    IWAVAX public immutable WAVAX;

    /// @notice USDC token (6 decimals on Avalanche)
    IERC20 public immutable USDC;

    /// @notice Pharaoh CL NonFungiblePositionManager
    INonfungiblePositionManager public immutable positionManager;

    /// @notice Pharaoh CL Factory
    IUniswapV3Factory public immutable factory;

    /// @notice Pharaoh SwapRouter
    ISwapRouter public immutable swapRouter;

    /// @notice Pool fee tier (30 bps = 3000)
    uint24 public immutable fee;

    // ─── State ────────────────────────────────────────────────────

    /// @notice Current NFT tokenId; 0 means no active position
    uint256 public tokenId;

    /// @notice Range half-width as a basis-point fraction of price.
    ///         Default 1000 = 10 % either side → ±10 % range.
    uint256 public rangeBps;

    /// @notice Slippage tolerance when providing liquidity / swapping (bps)
    uint256 public slippageBps;

    // ─── Events ───────────────────────────────────────────────────

    event Deposit(address indexed from, uint256 usdcAmount);
    event PositionMinted(uint256 indexed tokenId, int24 tickLower, int24 tickUpper);
    event LiquidityIncreased(uint256 indexed tokenId, uint128 liquidityAdded);
    event Rebalanced(uint256 oldTokenId, uint256 newTokenId, int24 tickLower, int24 tickUpper);
    event FeesClaimed(address indexed recipient, uint256 amount0, uint256 amount1);
    event RangeBpsUpdated(uint256 oldBps, uint256 newBps);
    event SlippageBpsUpdated(uint256 oldBps, uint256 newBps);
    event DustSwept(address indexed token, address indexed to, uint256 amount);

    // ─── Constructor ──────────────────────────────────────────────

    /**
     * @param _wavax           WAVAX token address
     * @param _usdc            USDC token address
     * @param _positionManager Pharaoh NonFungiblePositionManager
     * @param _factory         Pharaoh CL factory
     * @param _swapRouter      Pharaoh SwapRouter
     * @param _fee             Pool fee tier (e.g. 3000)
     * @param _rangeBps        Initial range half-width in bps (default 1000 = 10 %)
     * @param _slippageBps     Max slippage on swaps / mints in bps (default 50 = 0.5 %)
     */
    constructor(
        address _wavax,
        address _usdc,
        address _positionManager,
        address _factory,
        address _swapRouter,
        uint24  _fee,
        uint256 _rangeBps,
        uint256 _slippageBps
    ) Ownable(msg.sender) {
        require(_wavax           != address(0), "zero wavax");
        require(_usdc            != address(0), "zero usdc");
        require(_positionManager != address(0), "zero npm");
        require(_factory         != address(0), "zero factory");
        require(_swapRouter      != address(0), "zero router");
        require(_rangeBps  > 0 && _rangeBps  <= 5000, "rangeBps 1-5000");
        require(_slippageBps     <= 1000,             "slippage max 10%");

        WAVAX          = IWAVAX(_wavax);
        USDC           = IERC20(_usdc);
        positionManager = INonfungiblePositionManager(_positionManager);
        factory        = IUniswapV3Factory(_factory);
        swapRouter     = ISwapRouter(_swapRouter);
        fee            = _fee;
        rangeBps       = _rangeBps;
        slippageBps    = _slippageBps;
    }

    // ─── Receive ──────────────────────────────────────────────────

    /// @dev Accepts raw AVAX (from WAVAX.withdraw or direct sends)
    receive() external payable {}

    // ─── ERC-721 receiver ─────────────────────────────────────────

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // ─── Owner-only config ────────────────────────────────────────

    /**
     * @notice Update the price-range half-width.
     * @param _rangeBps New value in basis points (1–5000).
     */
    function setRangeBps(uint256 _rangeBps) external onlyOwner {
        require(_rangeBps > 0 && _rangeBps <= 5000, "rangeBps 1-5000");
        emit RangeBpsUpdated(rangeBps, _rangeBps);
        rangeBps = _rangeBps;
    }

    /**
     * @notice Update the slippage tolerance.
     * @param _slippageBps New value in basis points (0–1000).
     */
    function setSlippageBps(uint256 _slippageBps) external onlyOwner {
        require(_slippageBps <= 1000, "slippage max 10%");
        emit SlippageBpsUpdated(slippageBps, _slippageBps);
        slippageBps = _slippageBps;
    }

    // ─── Primary user action: deposit USDC ───────────────────────

    /**
     * @notice Deposit USDC into the managed CL position.
     *         Caller must have approved this contract to spend `usdcAmount`.
     *         ~50 % of USDC is swapped to WAVAX; the rest seeds the position
     *         alongside the acquired WAVAX.
     * @param usdcAmount Amount of USDC (6 decimals) to deposit.
     */
    function deposit(uint256 usdcAmount) external nonReentrant {
        require(usdcAmount > 0, "zero amount");
        USDC.safeTransferFrom(msg.sender, address(this), usdcAmount);
        emit Deposit(msg.sender, usdcAmount);

        _deployLiquidity();
    }

    // ─── Rebalance ────────────────────────────────────────────────

    /**
     * @notice Close the current position and reopen it centred on the
     *         live price.  Callable by owner or keeper.
     *         No requirement that the position be out-of-range; owner
     *         may call proactively.
     */
    function rebalance() external onlyOwner nonReentrant {
        require(tokenId != 0, "no active position");

        // 1. Collect any pending fees into this contract
        _collect(address(this));

        // 2. Remove all liquidity
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
        if (liquidity > 0) {
            positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId:     tokenId,
                    liquidity:   liquidity,
                    amount0Min:  0,
                    amount1Min:  0,
                    deadline:    block.timestamp
                })
            );
        }

        // 3. Collect the withdrawn tokens
        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId:    tokenId,
                recipient:  address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // 4. Burn the NFT
        uint256 oldTokenId = tokenId;
        positionManager.burn(tokenId);
        tokenId = 0;

        // 5. Determine which token is token0 / token1 in the pool
        address pool = factory.getPool(address(WAVAX), address(USDC), fee);
        require(pool != address(0), "pool not found");
        address _token0 = IUniswapV3Pool(pool).token0();

        // 6. Convert any leftover WAVAX or USDC into a balanced allocation.
        //    We keep both assets and let the NPM use them in the new range.
        uint256 wavaxBal = WAVAX.balanceOf(address(this));
        uint256 usdcBal  = USDC.balanceOf(address(this));

        // If we have WAVAX but no USDC, swap half WAVAX → USDC
        if (wavaxBal > 0 && usdcBal == 0) {
            _swapWAVAXToUSDC(wavaxBal / 2);
        }
        // If we have USDC but no WAVAX, swap half USDC → WAVAX
        if (usdcBal > 0 && wavaxBal == 0) {
            _swapUSDCToWAVAX(usdcBal / 2);
        }
        // If we have both, no swap needed — NPM will handle the ratio

        // 7. Open new position
        uint256 newTokenId = _mintPosition(_token0);

        emit Rebalanced(oldTokenId, newTokenId, _getTickLower(), _getTickUpper());
    }

    // ─── Claim fees ───────────────────────────────────────────────

    /**
     * @notice Collect all pending fees from the active position and
     *         send them to `recipient`.
     * @param recipient Address that receives the fee tokens.
     * @return amount0  Token0 fees collected.
     * @return amount1  Token1 fees collected.
     */
    function claimFees(address recipient)
        external
        onlyOwner
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(tokenId != 0,           "no active position");
        require(recipient != address(0), "zero recipient");
        (amount0, amount1) = _collect(recipient);
        emit FeesClaimed(recipient, amount0, amount1);
    }

    // ─── View helpers ─────────────────────────────────────────────

    /**
     * @notice Returns true if the current position is out of range.
     */
    function isOutOfRange() external view returns (bool) {
        if (tokenId == 0) return false;
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) =
            positionManager.positions(tokenId);
        address pool = factory.getPool(address(WAVAX), address(USDC), fee);
        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
        return currentTick < tickLower || currentTick >= tickUpper;
    }

    /**
     * @notice Returns live position data.
     */
    function getPosition()
        external
        view
        returns (
            uint256 _tokenId,
            int24   tickLower,
            int24   tickUpper,
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        _tokenId = tokenId;
        if (tokenId == 0) return (_tokenId, 0, 0, 0, 0, 0);
        (, , , , , tickLower, tickUpper, liquidity, , , tokensOwed0, tokensOwed1) =
            positionManager.positions(tokenId);
    }

    // ─── Dust sweep (safety) ──────────────────────────────────────

    /**
     * @notice Owner can retrieve any stranded ERC-20 tokens.
     *         Primarily a safety escape-hatch.
     */
    function sweepToken(address token, address to, uint256 amount)
        external
        onlyOwner
    {
        require(to != address(0), "zero to");
        IERC20(token).safeTransfer(to, amount);
        emit DustSwept(token, to, amount);
    }

    // ─── Internal logic ───────────────────────────────────────────

    /**
     * @dev  Core deployment routine.
     *       1. Swaps ~50 % of USDC balance to WAVAX.
     *       2. Mints (or increases) a position with all held tokens.
     */
    function _deployLiquidity() internal {
        uint256 usdcBal = USDC.balanceOf(address(this));
        require(usdcBal > 0, "no USDC to deploy");

        // Swap half USDC → WAVAX so we can seed both sides
        uint256 swapAmount = usdcBal / 2;
        if (swapAmount > 0) {
            _swapUSDCToWAVAX(swapAmount);
        }

        address pool = factory.getPool(address(WAVAX), address(USDC), fee);
        require(pool != address(0), "pool not found");
        address _token0 = IUniswapV3Pool(pool).token0();

        if (tokenId == 0) {
            // First deposit — mint a new NFT position
            uint256 newTokenId = _mintPosition(_token0);
            (int24 tL, int24 tU) = (_getTickLower(), _getTickUpper());
            emit PositionMinted(newTokenId, tL, tU);
        } else {
            // Subsequent deposit — add to existing position
            _increaseLiquidity(_token0);
        }
    }

    /**
     * @dev Mint a new NFT position centred on the current price.
     */
    function _mintPosition(address _token0) internal returns (uint256 newTokenId) {
        (int24 tL, int24 tU) = _computeTicks();

        (address t0, address t1, uint256 a0, uint256 a1) = _resolveTokenOrder(_token0);

        IERC20(t0).forceApprove(address(positionManager), a0);
        IERC20(t1).forceApprove(address(positionManager), a1);

        uint256 a0Min = (a0 * (10_000 - slippageBps)) / 10_000;
        uint256 a1Min = (a1 * (10_000 - slippageBps)) / 10_000;

        (newTokenId, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0:         t0,
                token1:         t1,
                fee:            fee,
                tickLower:      tL,
                tickUpper:      tU,
                amount0Desired: a0,
                amount1Desired: a1,
                amount0Min:     a0Min,
                amount1Min:     a1Min,
                recipient:      address(this),
                deadline:       block.timestamp
            })
        );

        tokenId = newTokenId;

        // Revoke any excess approval
        IERC20(t0).forceApprove(address(positionManager), 0);
        IERC20(t1).forceApprove(address(positionManager), 0);
    }

    /**
     * @dev Increase liquidity on the existing position using all held tokens.
     */
    function _increaseLiquidity(address _token0) internal {
        (address t0, address t1, uint256 a0, uint256 a1) = _resolveTokenOrder(_token0);

        IERC20(t0).forceApprove(address(positionManager), a0);
        IERC20(t1).forceApprove(address(positionManager), a1);

        uint256 a0Min = (a0 * (10_000 - slippageBps)) / 10_000;
        uint256 a1Min = (a1 * (10_000 - slippageBps)) / 10_000;

        (, uint128 liqAdded, , ) = positionManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId:        tokenId,
                amount0Desired: a0,
                amount1Desired: a1,
                amount0Min:     a0Min,
                amount1Min:     a1Min,
                deadline:       block.timestamp
            })
        );

        IERC20(t0).forceApprove(address(positionManager), 0);
        IERC20(t1).forceApprove(address(positionManager), 0);

        emit LiquidityIncreased(tokenId, liqAdded);
    }

    /**
     * @dev Collect fees from the position and send to `to`.
     */
    function _collect(address to)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId:    tokenId,
                recipient:  to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    // ─── Swap helpers ─────────────────────────────────────────────

    function _swapUSDCToWAVAX(uint256 usdcIn) internal returns (uint256 wavaxOut) {
        if (usdcIn == 0) return 0;
        USDC.forceApprove(address(swapRouter), usdcIn);
        wavaxOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn:           address(USDC),
                tokenOut:          address(WAVAX),
                fee:               fee,
                recipient:         address(this),
                deadline:          block.timestamp,
                amountIn:          usdcIn,
                amountOutMinimum:  0,   // owner accepts configured slippage on mint
                sqrtPriceLimitX96: 0
            })
        );
        USDC.forceApprove(address(swapRouter), 0);
    }

    function _swapWAVAXToUSDC(uint256 wavaxIn) internal returns (uint256 usdcOut) {
        if (wavaxIn == 0) return 0;
        WAVAX.approve(address(swapRouter), wavaxIn);
        usdcOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn:           address(WAVAX),
                tokenOut:          address(USDC),
                fee:               fee,
                recipient:         address(this),
                deadline:          block.timestamp,
                amountIn:          wavaxIn,
                amountOutMinimum:  0,
                sqrtPriceLimitX96: 0
            })
        );
        WAVAX.approve(address(swapRouter), 0);
    }

    // ─── Tick / range helpers ─────────────────────────────────────

    /**
     * @dev  Computes the tick range centred on the current pool price.
     *       rangeBps / 10000 = fractional half-width of the price range.
     *       E.g. rangeBps = 1000 (10 %) → priceLower = price * 0.90,
     *                                       priceUpper = price * 1.10
     *
     *       We derive ticks from the sqrt-price ratio:
     *         sqrtP_lower = sqrtP_current * sqrt(1 - r)
     *         sqrtP_upper = sqrtP_current * sqrt(1 + r)
     *       where r = rangeBps / 10000.
     *
     *       For simplicity we use the pool's current tick and add an
     *       integer tick offset derived from log approximation, then
     *       snap to the nearest multiple of tickSpacing.
     */
    function _computeTicks() internal view returns (int24 tickLower, int24 tickUpper) {
        address pool = factory.getPool(address(WAVAX), address(USDC), fee);
        require(pool != address(0), "pool not found");

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
        int24 spacing = IUniswapV3Pool(pool).tickSpacing();

        // Number of ticks corresponding to ±rangeBps.
        // log_1.0001(1 + r) ≈ r / 0.0001  (for small r)
        // Ticks per unit: 1 tick ≈ 0.01 % price change.
        // tickOffset = rangeBps * 100   (e.g. 1000 bps → 100 000 ticks)
        int24 tickOffset = int24(int256(rangeBps) * 100);

        tickLower = _snapDown(currentTick - tickOffset, spacing);
        tickUpper = _snapUp  (currentTick + tickOffset, spacing);

        // Guard against hitting absolute limits
        if (tickLower < TickMath.MIN_TICK) tickLower = _snapUp(TickMath.MIN_TICK, spacing);
        if (tickUpper > TickMath.MAX_TICK) tickUpper = _snapDown(TickMath.MAX_TICK, spacing);
        require(tickLower < tickUpper, "degenerate range");
    }

    function _getTickLower() internal view returns (int24 tL) {
        (tL, ) = _computeTicks();
    }

    function _getTickUpper() internal view returns (int24 tU) {
        (, tU) = _computeTicks();
    }

    function _snapDown(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 remainder = tick % spacing;
        if (remainder < 0) remainder += spacing;
        return tick - remainder;
    }

    function _snapUp(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 snapped = _snapDown(tick, spacing);
        return snapped == tick ? tick : snapped + spacing;
    }

    /**
     * @dev  Returns (token0, token1, amount0, amount1) in pool order.
     */
    function _resolveTokenOrder(address _token0)
        internal
        view
        returns (
            address t0,
            address t1,
            uint256 a0,
            uint256 a1
        )
    {
        bool wavaxIsToken0 = _token0 == address(WAVAX);
        t0 = wavaxIsToken0 ? address(WAVAX) : address(USDC);
        t1 = wavaxIsToken0 ? address(USDC)  : address(WAVAX);
        uint256 wavaxBal = WAVAX.balanceOf(address(this));
        uint256 usdcBal  = USDC.balanceOf(address(this));
        a0 = wavaxIsToken0 ? wavaxBal : usdcBal;
        a1 = wavaxIsToken0 ? usdcBal  : wavaxBal;
    }
}
