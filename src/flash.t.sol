// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.6.12;

import "ds-test/test.sol";
import "ds-value/value.sol";
import "ds-token/token.sol";
import {Vat}              from "dss/vat.sol";
import {Spotter}          from "dss/spot.sol";
import {Vow}              from "dss/vow.sol";
import {GemJoin, USDVJoin} from "dss/join.sol";
import {Token}              from "dss/usdv.sol";

import "./flash.sol";
import "./base/FlashLoanReceiverBase.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract TestVat is Vat {
    function mint(address usr, uint256 rad) public {
        usdv[usr] += rad;
    }
}

contract TestVow is Vow {
    constructor(address vat, address flapper, address flopper)
        public Vow(vat, flapper, flopper) {}
    // Total deficit
    function Awe() public view returns (uint256) {
        return vat.sin(address(this));
    }
    // Total surplus
    function Joy() public view returns (uint256) {
        return vat.usdv(address(this));
    }
    // Unqueued, pre-auction debt
    function Woe() public view returns (uint256) {
        return sub(sub(Awe(), Sin), Ash);
    }
}

contract TestDoNothingReceiver is FlashLoanReceiverBase {

    // --- Init ---
    constructor(address _flash) FlashLoanReceiverBase(_flash) public {
    }

    function onFlashLoan(address _sender, address _token, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender; _token; _amount; _fee;
        // Don't do anything
        return CALLBACK_SUCCESS;
    }

    function onVatUsdvFlashLoan(address _sender, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender; _amount; _fee;
        // Don't do anything
        return CALLBACK_SUCCESS_VAT_USDV;
    }

}

contract TestImmediatePaybackReceiver is FlashLoanReceiverBase {

    // --- Init ---
    constructor(address _flash) FlashLoanReceiverBase(_flash) public {
    }

    function onFlashLoan(address _sender, address _token, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender; _token;
        // Just pay back the original amount
        approvePayback(add(_amount, _fee));

        return CALLBACK_SUCCESS;
    }

    function onVatUsdvFlashLoan(address _sender, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender;
        // Just pay back the original amount
        payBackVatUsdv(add(_amount, _fee));

        return CALLBACK_SUCCESS_VAT_USDV;
    }

}

contract TestLoanAndPaybackReceiver is FlashLoanReceiverBase {

    uint256 mint;

    // --- Init ---
    constructor(address _flash) FlashLoanReceiverBase(_flash) public {
    }

    function setMint(uint256 _mint) public {
        mint = _mint;
    }

    function onFlashLoan(address _sender, address _token, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender; _token;
        TestVat(address(flash.vat())).mint(address(this), rad(mint));
        flash.vat().hope(address(flash.USDVJoin()));
        flash.usdvJoin().exit(address(this), mint);

        approvePayback(add(_amount, _fee));

        return CALLBACK_SUCCESS;
    }

    function onVatUsdvFlashLoan(address _sender, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender;
        TestVat(address(flash.vat())).mint(address(this), rad(mint));

        payBackVatUsdv(add(_amount, _fee));

        return CALLBACK_SUCCESS_VAT_USDV;
    }

}

contract TestLoanAndPaybackAllReceiver is FlashLoanReceiverBase {

    uint256 mint;

    // --- Init ---
    constructor(address _flash) FlashLoanReceiverBase(_flash) public {
    }

    function setMint(uint256 _mint) public {
        mint = _mint;
    }

    function onFlashLoan(address _sender, address _token, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender; _token; _fee;
        TestVat(address(flash.vat())).mint(address(this), rad(mint));
        flash.vat().hope(address(flash.usdvJoin()));
        flash.usdvJoin().exit(address(this), mint);

        approvePayback(add(_amount, mint));

        return CALLBACK_SUCCESS;
    }

    function onVatUsdvFlashLoan(address _sender, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender; _fee;
        TestVat(address(flash.vat())).mint(address(this), rad(mint));

        payBackVatUsdv(add(_amount, rad(mint)));

        return CALLBACK_SUCCESS_VAT_USDV;
    }

}

contract TestLoanAndPaybackDataReceiver is FlashLoanReceiverBase {

    // --- Init ---
    constructor(address _flash) FlashLoanReceiverBase(_flash) public {
    }

    function onFlashLoan(address _sender, address _token, uint256 _amount, uint256 _fee, bytes calldata _data) external override returns (bytes32) {
        _sender; _token;
        (uint256 mint) = abi.decode(_data, (uint256));
        TestVat(address(flash.vat())).mint(address(this), rad(mint));
        flash.vat().hope(address(flash.usdvJoin()));
        flash.usdvJoin().exit(address(this), mint);

        approvePayback(add(_amount, _fee));

        return CALLBACK_SUCCESS;
    }

    function onVatUsdvFlashLoan(address _sender, uint256 _amount, uint256 _fee, bytes calldata _data) external override returns (bytes32) {
        _sender;
        (uint256 mint) = abi.decode(_data, (uint256));
        TestVat(address(flash.vat())).mint(address(this), rad(mint));

        payBackVatUsdv(add(_amount, _fee));

        return CALLBACK_SUCCESS_VAT_USDV;
    }

}

contract TestReentrancyReceiver is FlashLoanReceiverBase {

    TestImmediatePaybackReceiver immediatePaybackReceiver;

    // --- Init ---
    constructor(address _flash) FlashLoanReceiverBase(_flash) public {
        immediatePaybackReceiver = new TestImmediatePaybackReceiver(_flash);
    }

    function onFlashLoan(address _sender, address _token, uint256 _amount, uint256 _fee, bytes calldata _data) external override returns (bytes32) {
        _sender;
        flash.flashLoan(immediatePaybackReceiver, _token, _amount + _fee, _data);

        approvePayback(add(_amount, _fee));

        return CALLBACK_SUCCESS;
    }

    function onVatUsdvFlashLoan(address _sender, uint256 _amount, uint256 _fee, bytes calldata _data) external override returns (bytes32) {
        _sender;
        flash.vatUsdvFlashLoan(immediatePaybackReceiver, _amount + _fee, _data);

        payBackVatUsdv(add(_amount, _fee));

        return CALLBACK_SUCCESS_VAT_usdv;
    }

}

contract TestDEXTradeReceiver is FlashLoanReceiverBase {

    Token usdv;
    USDVJoin usdvJoin;
    DSToken gold;
    GemJoin gemA;
    bytes32 ilk;

    // --- Init ---
    constructor(address flash_, address usdv_, address usdvJoin_, address gold_, address gemA_, bytes32 ilk_) FlashLoanReceiverBase(flash_) public {
        usdv = Token(usdv_);
        usdvJoin = USDVJoin(usdvJoin_);
        gold = DSToken(gold_);
        gemA = GemJoin(gemA_);
        ilk = ilk_;
    }

    function onFlashLoan(address _sender, address _token, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender; _token;
        address me = address(this);
        uint256 totalDebt = _amount + _fee;
        uint256 goldAmount = totalDebt * 3;

        // Perform a "trade"
        usdv.burn(me, _amount);
        gold.mint(me, goldAmount);

        // Mint some more usdv to repay the original loan
        gold.approve(address(gemA));
        gemA.join(me, goldAmount);
        Vat(address(flash.vat())).frob(ilk, me, me, me, int256(goldAmount), int256(totalDebt));
        flash.vat().hope(address(flash.usdvJoin()));
        flash.usdvJoin().exit(me, totalDebt);

        approvePayback(add(_amount, _fee));

        return CALLBACK_SUCCESS;
    }

    function onVatUsdvFlashLoan(address _sender, uint256 _amount, uint256 _fee, bytes calldata _data) external override returns (bytes32) {
        _sender; _amount; _fee; _data;
        return CALLBACK_SUCCESS_VAT_USDV;
    }

}

contract TestBadReturn is FlashLoanReceiverBase {

    bytes32 constant BAD_HASH = keccak256("my bad hash");

    // --- Init ---
    constructor(address _flash) FlashLoanReceiverBase(_flash) public {
    }

    function onFlashLoan(address _sender, address _token, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender; _token;
        approvePayback(add(_amount, _fee));

        return BAD_HASH;
    }

    function onVatUsdvFlashLoan(address _sender, uint256 _amount, uint256 _fee, bytes calldata) external override returns (bytes32) {
        _sender;
        payBackVatUsdv(add(_amount, _fee));

        return BAD_HASH;
    }

}

contract TestNoCallbacks {

}

contract DssFlashTest is DSTest {
    Hevm hevm;

    address me;

    TestVat vat;
    Spotter spot;
    TestVow vow;
    DSValue pip;
    GemJoin gemA;
    DSToken gold;
    USDVJoin usdvJoin;
    Token usdv;

    DssFlash flash;

    TestDoNothingReceiver doNothingReceiver;
    TestImmediatePaybackReceiver immediatePaybackReceiver;
    TestLoanAndPaybackReceiver mintAndPaybackReceiver;
    TestLoanAndPaybackAllReceiver mintAndPaybackAllReceiver;
    TestLoanAndPaybackDataReceiver mintAndPaybackDataReceiver;
    TestReentrancyReceiver reentrancyReceiver;
    TestDEXTradeReceiver dexTradeReceiver;
    TestBadReturn badReturn;
    TestNoCallbacks noCallbacks;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    bytes32 constant ilk = "gold";

    uint256 constant RATE_ONE_PCT = 10 ** 16;

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        me = address(this);

        vat = new TestVat();
        vat = vat;

        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        vow = new TestVow(address(vat), address(0), address(0));

        gold = new DSToken("GEM");
        gold.mint(1000 ether);

        vat.init(ilk);

        gemA = new GemJoin(address(vat), ilk, address(gold));
        vat.rely(address(gemA));
        gold.approve(address(gemA));
        gemA.join(me, 1000 ether);

        usdv = new Token(0);
        usdvJoin = new UsdvJoin(address(vat), address(usdv));
        vat.rely(address(usdvJoin));
        usdv.rely(address(usdvJoin));

        flash = new DssFlash(address(usdvJoin), address(vow));

        pip = new DSValue();
        pip.poke(bytes32(uint256(5 ether))); // Spot = $2.5

        spot.file(ilk, bytes32("pip"), address(pip));
        spot.file(ilk, bytes32("mat"), ray(2 ether));
        spot.poke(ilk);

        vat.file(ilk, "line", rad(1000 ether));
        vat.file("Line",      rad(1000 ether));

        gold.approve(address(vat));

        assertEq(vat.gem(ilk, me), 1000 ether);
        assertEq(vat.usdv(me), 0);
        vat.frob(ilk, me, me, me, 40 ether, 100 ether);
        assertEq(vat.gem(ilk, me), 960 ether);
        assertEq(vat.usdv(me), rad(100 ether));

        // Basic auth and 1000 usdv debt ceiling
        flash.file("max", 1000 ether);
        vat.rely(address(flash));

        doNothingReceiver = new TestDoNothingReceiver(address(flash));
        immediatePaybackReceiver = new TestImmediatePaybackReceiver(address(flash));
        mintAndPaybackReceiver = new TestLoanAndPaybackReceiver(address(flash));
        mintAndPaybackAllReceiver = new TestLoanAndPaybackAllReceiver(address(flash));
        mintAndPaybackDataReceiver = new TestLoanAndPaybackDataReceiver(address(flash));
        reentrancyReceiver = new TestReentrancyReceiver(address(flash));
        dexTradeReceiver = new TestDEXTradeReceiver(address(flash), address(usdv), address(usdvJoin), address(gold), address(gemA), ilk);
        badReturn = new TestBadReturn(address(flash));
        noCallbacks = new TestNoCallbacks();
        usdv.rely(address(dexTradeReceiver));
    }

    function test_mint_no_fee_payback () public {
        flash.vatUsdvFlashLoan(immediatePaybackReceiver, rad(10 ether), "");
        flash.flashLoan(immediatePaybackReceiver, address(usdv), 10 ether, "");

        assertEq(vat.usdv(address(immediatePaybackReceiver)), 0);
        assertEq(vat.sin(address(immediatePaybackReceiver)), 0);
        assertEq(vat.usdv(address(flash)), 0);
        assertEq(vat.sin(address(flash)), 0);
    }

    // test mint() for _amount == 0
    function test_mint_zero_amount () public {
        flash.vatUsdvFlashLoan(immediatePaybackReceiver, 0, "");
        flash.flashLoan(immediatePaybackReceiver, address(usdv), 0, "");
    }

    // test mint() for _amount > line
    function testFail_mint_amount_over_line1 () public {
        flash.vatUsdvFlashLoan(immediatePaybackReceiver, rad(1001 ether), "");
    }
    function testFail_mint_amount_over_line2 () public {
        flash.flashLoan(immediatePaybackReceiver, address(usdv), 1001 ether, "");
    }

    // test line == 0 means flash minting is halted
    function testFail_mint_line_zero1 () public {
        flash.file("max", 0);

        flash.vatUsdvFlashLoan(immediatePaybackReceiver, rad(10 ether), "");
    }
    function testFail_mint_line_zero2 () public {
        flash.file("max", 0);

        flash.flashLoan(immediatePaybackReceiver, address(usdv), 10 ether, "");
    }

    // test unauthorized suck() reverts
    function testFail_mint_unauthorized_suck1 () public {
        vat.deny(address(flash));

        flash.vatUsdvFlashLoan(immediatePaybackReceiver, rad(10 ether), "");
    }
    function testFail_mint_unauthorized_suck2 () public {
        vat.deny(address(flash));

        flash.flashLoan(immediatePaybackReceiver, address(usdv), 10 ether, "");
    }

    // test happy path onFlashLoan() returns vat.usdv() == add(_amount, fee)
    //       Make sure we test core system accounting balances before and after.
    function test_mint_with_fee () public {
        flash.file("toll", RATE_ONE_PCT);
        mintAndPaybackReceiver.setMint(10 ether);

        flash.vatUsdvFlashLoan(mintAndPaybackReceiver, rad(100 ether), "");
        flash.accrue();

        assertEq(vow.Joy(), rad(1 ether));
        assertEq(vat.usdv(address(mintAndPaybackReceiver)), rad(9 ether));

        flash.flashLoan(mintAndPaybackReceiver, address(usdv), 100 ether, "");
        flash.accrue();

        assertEq(vow.Joy(), rad(2 ether));
        assertEq(vat.usdv(address(mintAndPaybackReceiver)), rad(9 ether));
        assertEq(usdv.balanceOf(address(mintAndPaybackReceiver)), 9 ether);
    }

    // Test mint doesn't fail when contract already has a usdv balance
    function test_preexisting_usdv_in_flash () public {
        flash.file("toll", RATE_ONE_PCT);

        // Move some collateral to the flash so it preexists the loan
        vat.move(address(this), address(flash), rad(1 ether));

        mintAndPaybackReceiver.setMint(10 ether);

        flash.vatUsdvFlashLoan(mintAndPaybackReceiver, rad(100 ether), "");
        flash.accrue();

        assertEq(vow.Joy(), rad(2 ether));
        assertEq(vat.usdv(address(mintAndPaybackReceiver)), rad(9 ether));
        // Ensure pre-existing amount remains in flash
        assertEq(vat.usdv(address(flash)), 0);

        // Test for erc20 usdv
        usdv.mint(address(flash), 1 ether);

        flash.flashLoan(mintAndPaybackReceiver, address(usdv), 100 ether, "");
        flash.accrue();

        assertEq(vow.Joy(), rad(3 ether));
        assertEq(vat.usdv(address(mintAndPaybackReceiver)), rad(9 ether));
        assertEq(usdv.balanceOf(address(mintAndPaybackReceiver)), 9 ether);
        // Ensure pre-existing amount remains in flash
        assertEq(vat.usdv(address(flash)), 0);
        assertEq(usdv.balanceOf(address(flash)), 1 ether);
        flash.convert();
        assertEq(vat.usdv(address(flash)), rad(1 ether));
        assertEq(usdv.balanceOf(address(flash)), 0);
        flash.accrue();
        assertEq(vow.Joy(), rad(4 ether));
        assertEq(vat.usdv(address(flash)), 0);
        assertEq(usdv.balanceOf(address(flash)), 0);
    }

    // test onFlashLoan that return vat.usdv() < add(_amount, fee) fails
    function testFail_mint_insufficient_usdv1 () public {
        flash.file("toll", 5 * RATE_ONE_PCT);
        mintAndPaybackAllReceiver.setMint(4 ether);

        flash.vatUsdvFlashLoan(mintAndPaybackAllReceiver, rad(100 ether), "");
    }
    function testFail_mint_insufficient_usdv2 () public {
        flash.file("toll", 5 * RATE_ONE_PCT);
        mintAndPaybackAllReceiver.setMint(4 ether);

        flash.flashLoan(mintAndPaybackAllReceiver, address(usdv), 100 ether, "");
    }

    // test onFlashLoan that return vat.usdv() > add(_amount, fee)
    // ERC 3156 says to use approve instead of transfer so you never take more than you require
    // This is an intentional difference between ERC20 Flash Mint and Vat usdv Flash Mint
    function test_mint_too_much_usdv2 () public {
        flash.file("toll", 5 * RATE_ONE_PCT);
        mintAndPaybackAllReceiver.setMint(10 ether);

        // First mint overpays
        flash.flashLoan(mintAndPaybackAllReceiver, address(usdv), 100 ether, "");
        flash.accrue();

        assertEq(vow.Joy(), rad(5 ether));
        assertEq(usdv.balanceOf(address(flash)), 0 ether);
    }
    // The vat usdv version will allow overpays
    function test_mint_too_much_usdv1 () public {
        flash.file("toll", 5 * RATE_ONE_PCT);
        mintAndPaybackAllReceiver.setMint(10 ether);

        // First mint overpays
        flash.vatUsdvFlashLoan(mintAndPaybackAllReceiver, rad(100 ether), "");
        flash.accrue();

        assertEq(vow.Joy(), rad(10 ether));
        assertEq(vat.usdv(address(flash)), 0);
    }

    // test that data sends properly
    function test_mint_data () public {
        flash.file("toll", 5 * RATE_ONE_PCT);
        uint256 mintAmount = 8 ether;

        flash.vatUsdvFlashLoan(mintAndPaybackDataReceiver, rad(100 ether), abi.encodePacked(mintAmount));
        flash.accrue();

        assertEq(vow.Joy(), rad(5 ether));
        assertEq(vat.usdv(address(mintAndPaybackDataReceiver)), rad(3 ether));

        flash.flashLoan(mintAndPaybackDataReceiver, address(usdv), 100 ether, abi.encodePacked(mintAmount));
        flash.accrue();

        assertEq(vow.Joy(), rad(10 ether));
        assertEq(usdv.balanceOf(address(mintAndPaybackDataReceiver)), 3 ether);
    }

    // test reentrancy disallowed
    function testFail_mint_reentrancy1 () public {
        flash.vatUsdvFlashLoan(reentrancyReceiver, rad(100 ether), "");
    }
    function testFail_mint_reentrancy2 () public {
        flash.flashLoan(reentrancyReceiver, address(usdv), rad(100 ether), "");
    }

    // test trading flash minted usdv for gold and minting more usdv
    function test_dex_trade () public {
        // Set the owner temporarily to allow the receiver to mint
        gold.setOwner(address(dexTradeReceiver));

        flash.flashLoan(dexTradeReceiver, address(usdv), 100 ether, "");
    }

    // test excessive max debt ceiling
    function testFail_line_limit () public {
        flash.file("max", 10 ** 45 + 1);
    }

    function test_max_flash_loan () public {
        assertEq(flash.maxFlashLoan(address(usdv)), 1000 ether);
        assertEq(flash.maxFlashLoan(address(usdvJoin)), 0);  // Any other address should be 0 as per the spec
    }

    function test_flash_fee () public {
        flash.file("toll", 5 * RATE_ONE_PCT);
        assertEq(flash.flashFee(address(usdv), 100 ether), 5 ether);
    }

    function testFail_flash_fee () public {
        flash.file("toll", 5 * RATE_ONE_PCT);
        flash.flashFee(address(usdvJoin), 100 ether);  // Any other address should fail
    }

    function testFail_bad_token () public {
        flash.flashLoan(immediatePaybackReceiver, address(usdvJoin), 100 ether, "");
    }

    function testFail_bad_return_hash1 () public {
        flash.vatUsdvFlashLoan(badReturn, rad(100 ether), "");
    }
    function testFail_bad_return_hash2 () public {
        flash.flashLoan(badReturn, address(usdv), 100 ether, "");
    }

    function testFail_no_callbacks1 () public {
        flash.vatUsdvFlashLoan(IVatUsdvFlashBorrower(address(noCallbacks)), rad(100 ether), "");
    }
    function testFail_no_callbacks2 () public {
        flash.flashLoan(IERC3156FlashBorrower(address(noCallbacks)), address(usdv), 100 ether, "");
    }

}
