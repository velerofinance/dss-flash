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

pragma solidity 0.6.12;

import "./interface/IERC3156FlashLender.sol";
import "./interface/IERC3156FlashBorrower.sol";
import "./interface/IVatUsdvFlashLender.sol";

interface UsdvLike {
    function balanceOf(address) external returns (uint256);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface UsdvJoinLike {
    function usdv() external view returns (address);
    function vat() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface VatLike {
    function hope(address) external;
    function usdv(address) external view returns (uint256);
    function move(address, address, uint256) external;
    function heal(uint256) external;
    function suck(address, address, uint256) external;
}

contract DssFlash is IERC3156FlashLender, IVatUsdvFlashLender {

    // --- Auth ---
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    mapping (address => uint256) public wards;
    modifier auth {
        require(wards[msg.sender] == 1, "DssFlash/not-authorized");
        _;
    }

    // --- Data ---
    VatLike     public immutable vat;
    UsdvJoinLike public immutable usdvJoin;
    UsdvLike     public immutable usdv;
    address     public immutable vow;       // vow intentionally set immutable to save gas

    uint256     public  max;     // Maximum borrowable USDV  [wad]
    uint256     public  toll;    // Fee                     [wad = 100%]
    uint256     private locked;  // Reentrancy guard

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    bytes32 public constant CALLBACK_SUCCESS_VAT_USDV = keccak256("VatUsdvFlashBorrower.onVatUsdvFlashLoan");

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event FlashLoan(address indexed receiver, address token, uint256 amount, uint256 fee);
    event VatUsdvFlashLoan(address indexed receiver, uint256 amount, uint256 fee);

    modifier lock {
        require(locked == 0, "DssFlash/reentrancy-guard");
        locked = 1;
        _;
        locked = 0;
    }

    // --- Init ---
    constructor(address usdvJoin_, address vow_) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        VatLike vat_ = vat = VatLike(UsdvJoinLike(usdvJoin_).vat());
        usdvJoin = UsdvJoinLike(usdvJoin_);
        UsdvLike usdv_ = usdv = UsdvLike(usdvJoinLike(usdvJoin_).usdv());
        vow = vow_;

        vat_.hope(usdvJoin_);
        usdv_.approve(usdvJoin_, type(uint256).max);
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "max") {
            // Add an upper limit of 10^27 USDV to avoid breaking technical assumptions of USDV << 2^256 - 1
            require((max = data) <= RAD, "DssFlash/ceiling-too-high");
        } else if (what == "toll") toll = data;
        else revert("DssFlash/file-unrecognized-param");
        emit File(what, data);
    }

    // --- ERC 3156 Spec ---
    function maxFlashLoan(
        address token
    ) external override view returns (uint256) {
        if (token == address(usdv) && locked == 0) {
            return max;
        } else {
            return 0;
        }
    }
    function flashFee(
        address token,
        uint256 amount
    ) external override view returns (uint256) {
        require(token == address(usdv), "DssFlash/token-unsupported");

        return _mul(amount, toll) / WAD;
    }
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override lock returns (bool) {
        require(token == address(usdv), "DssFlash/token-unsupported");
        require(amount <= max, "DssFlash/ceiling-exceeded");

        uint256 amt = _mul(amount, RAY);
        uint256 fee = _mul(amount, toll) / WAD;
        uint256 total = _add(amount, fee);

        vat.suck(address(this), address(this), amt);
        USDVJoin.exit(address(receiver), amount);

        emit FlashLoan(address(receiver), token, amount, fee);

        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == CALLBACK_SUCCESS,
            "DssFlash/callback-failed"
        );

        USDV.transferFrom(address(receiver), address(this), total); // The fee is also enforced here
        USDVJoin.join(address(this), total);
        vat.heal(amt);

        return true;
    }

    // --- Vat USDV Flash Loan ---
    function vatUsdvFlashLoan(
        IVatUsdvFlashBorrower receiver,          // address of conformant IVatUsdvFlashBorrower
        uint256 amount,                         // amount to flash loan [rad]
        bytes calldata data                     // arbitrary data to pass to the receiver
    ) external override lock returns (bool) {
        require(amount <= _mul(max, RAY), "DssFlash/ceiling-exceeded");

        uint256 prev = vat.usdv(address(this));
        uint256 fee = _mul(amount, toll) / WAD;

        vat.suck(address(this), address(receiver), amount);

        emit VatUsdvFlashLoan(address(receiver), amount, fee);

        require(
            receiver.onVatUsdvFlashLoan(msg.sender, amount, fee, data) == CALLBACK_SUCCESS_VAT_USDV,
            "DssFlash/callback-failed"
        );

        vat.heal(amount);
        require(vat.usdv(address(this)) >= _add(prev, fee), "DssFlash/insufficient-fee");

        return true;
    }

    function convert() external lock {
        usdvJoin.join(address(this), usdv.balanceOf(address(this)));
    }

    function accrue() external lock {
        vat.move(address(this), vow, vat.usdv(address(this)));
    }
}
