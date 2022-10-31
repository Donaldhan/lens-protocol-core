// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Errors} from '../../libraries/Errors.sol';
import {Events} from '../../libraries/Events.sol';
import {IModuleGlobals} from '../../interfaces/IModuleGlobals.sol';

/**
 * @title FeeModuleBase
 * @author Lens Protocol
 * 费用模块基础类
 * @notice This is an abstract contract to be inherited from by modules that require basic fee functionality. It
 * contains getters for module globals parameters as well as a validation function to check expected data.
 */
abstract contract FeeModuleBase {
    uint16 internal constant BPS_MAX = 10000;

    address public immutable MODULE_GLOBALS; //全局module

    constructor(address moduleGlobals) {
        if (moduleGlobals == address(0)) revert Errors.InitParamsInvalid();
        MODULE_GLOBALS = moduleGlobals;
        emit Events.FeeModuleBaseConstructed(moduleGlobals, block.timestamp);
    }
    //token是否为白名单
    function _currencyWhitelisted(address currency) internal view returns (bool) {
        return IModuleGlobals(MODULE_GLOBALS).isCurrencyWhitelisted(currency);
    }
    ///获取金库地址，及金库征收的collect 百分点BPS
    function _treasuryData() internal view returns (address, uint16) {
        return IModuleGlobals(MODULE_GLOBALS).getTreasuryData();
    }
    //校验token 及数量数据
    function _validateDataIsExpected(
        bytes calldata data,
        address currency,
        uint256 amount
    ) internal pure {
        (address decodedCurrency, uint256 decodedAmount) = abi.decode(data, (address, uint256));
        if (decodedAmount != amount || decodedCurrency != currency)
            revert Errors.ModuleDataMismatch();
    }
}
