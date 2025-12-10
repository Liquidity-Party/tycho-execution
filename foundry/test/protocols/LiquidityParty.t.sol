// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {
    IERC20
} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {RestrictTransferFrom} from "../../src/RestrictTransferFrom.sol";
import {
    LiquidityPartyExecutor,
    IPartyPool
} from "../../src/executors/LiquidityPartyExecutor.sol";
import {Constants} from "../Constants.sol";
import {Permit2TestHelper} from "../Permit2TestHelper.sol";
import {TestUtils} from "../TestUtils.sol";
import {LiquidityPartyExecutorExposed} from "./LiquidityParty.t.sol";

contract LiquidityPartyExecutorExposed is LiquidityPartyExecutor {
    constructor(address _permit2) LiquidityPartyExecutor(_permit2) {}

    function decodeParams(bytes calldata data)
        external
        pure
        returns (
            IPartyPool pool,
            address tokenIn,
            uint8 indexIn,
            uint8 indexOut,
            TransferType transferType,
            address receiver
        )
    {
        return _decodeData(data);
    }
}

contract LiquidityPartyExecutorTest is Constants, Permit2TestHelper, TestUtils {
    using SafeERC20 for IERC20;

    LiquidityPartyExecutorExposed private executor;
    IPartyPool private constant POOL =
        IPartyPool(0x2A804e94500AE379ee0CcC423a67B07cc0aF548C);
    IERC20 private constant INPUT_TOKEN =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
    uint8 private constant INPUT_INDEX = 3;
    uint256 private constant AMOUNT_IN = 30428379889; // 30 gwei, 0.1% of the pool's WETH
    IERC20 private constant OUTPUT_TOKEN =
        IERC20(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE); // SHIB
    uint8 private constant OUTPUT_INDEX = 9;
    uint256 private constant EXPECTED_AMOUNT_OUT = 11480220066406156603; // about 115 SHIB
    uint256 private constant FORK_BLOCK = 23978797;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), FORK_BLOCK);
        executor = new LiquidityPartyExecutorExposed(PERMIT2_ADDRESS);
    }

    function testDecodeParams() public view {
        bytes memory params = abi.encodePacked(
            POOL,
            INPUT_TOKEN,
            INPUT_INDEX,
            OUTPUT_INDEX,
            ALICE,
            RestrictTransferFrom.TransferType.Transfer
        );

        (
            IPartyPool pool,
            address tokenIn,
            uint8 indexIn,
            uint8 indexOut,
            RestrictTransferFrom.TransferType transferType,
            address receiver
        ) = executor.decodeParams(params);

        assertEq(address(pool), address(POOL));
        assertEq(address(tokenIn), address(INPUT_TOKEN));
        assertEq(indexIn, INPUT_INDEX);
        assertEq(indexOut, OUTPUT_INDEX);
        assertEq(
            uint8(transferType),
            uint8(RestrictTransferFrom.TransferType.Transfer)
        );
        assertEq(receiver, ALICE);
    }

    function testDecodeParamsInvalidDataLength() public {
        bytes memory invalidParams =
            abi.encodePacked(WETH_ADDR, address(2), address(3));
        vm.expectRevert();
        executor.decodeParams(invalidParams);
    }

    function testSwapWithTransfer() public {
        bytes memory protocolData = abi.encodePacked(
            POOL,
            INPUT_TOKEN,
            INPUT_INDEX,
            OUTPUT_INDEX,
            BOB,
            RestrictTransferFrom.TransferType.Transfer
        );

        deal(address(INPUT_TOKEN), address(executor), AMOUNT_IN);
        uint256 amountOut = executor.swap(AMOUNT_IN, protocolData);

        assertEq(amountOut, EXPECTED_AMOUNT_OUT);
        assertGe(OUTPUT_TOKEN.balanceOf(BOB), EXPECTED_AMOUNT_OUT);
    }

    function testSwapNoTransfer() public {
        bytes memory protocolData = abi.encodePacked(
            POOL,
            INPUT_TOKEN,
            INPUT_INDEX,
            OUTPUT_INDEX,
            BOB,
            RestrictTransferFrom.TransferType.None
        );

        deal(address(INPUT_TOKEN), address(this), AMOUNT_IN);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        INPUT_TOKEN.transfer(address(POOL), AMOUNT_IN);
        uint256 amountOut = executor.swap(AMOUNT_IN, protocolData);

        assertEq(amountOut, EXPECTED_AMOUNT_OUT);
        assertGe(OUTPUT_TOKEN.balanceOf(BOB), EXPECTED_AMOUNT_OUT);
    }

    function testSwapIntegration() public {
        bytes memory protocolData =
            loadCallDataFromFile("test_encode_liquidityparty");
        deal(address(INPUT_TOKEN), address(executor), AMOUNT_IN);
        uint256 amountOut = executor.swap(AMOUNT_IN, protocolData);

        uint256 finalBalance = OUTPUT_TOKEN.balanceOf(BOB);
        assertEq(amountOut, EXPECTED_AMOUNT_OUT);
        assertGe(finalBalance, amountOut);
    }

    function testSwapFailureKilledPool() public {
        // Killed pools should not even appear as protocol components, but we test an attempted swap anyway.
        // This address is a pool that was killed (permanent redeem-only mode)
        address killedPool = address(0xC0A908477FFeff658699182bEB5EcaF1D46B3ddB);
        bytes memory protocolData = abi.encodePacked(
            killedPool,
            INPUT_TOKEN,
            INPUT_INDEX,
            OUTPUT_INDEX,
            BOB,
            RestrictTransferFrom.TransferType.None
        );

        deal(address(INPUT_TOKEN), address(executor), AMOUNT_IN);
        vm.expectRevert();
        executor.swap(AMOUNT_IN, protocolData);
    }

    function testExportContract() public {
        exportRuntimeBytecode(address(executor), "LiquidityParty");
    }
}
