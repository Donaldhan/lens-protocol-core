// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Events} from '../../libraries/Events.sol';
import {DataTypes} from '../../libraries/DataTypes.sol';
import {Errors} from '../../libraries/Errors.sol';

/**
 * @title LensMultiState
 *
 * @notice This is an abstract contract that implements internal LensHub state setting and validation.
 *
 * whenNotPaused: Either publishingPaused or Unpaused.
 * whenPublishingEnabled: When Unpaused only.
 */
abstract contract LensMultiState {
    //状态
    DataTypes.ProtocolState private _state;
    //启动状态
    modifier whenNotPaused() {
        _validateNotPaused();
        _;
    }
    //发布状态开启
    modifier whenPublishingEnabled() {
        _validatePublishingEnabled();
        _;
    }

    /**
     * @notice Returns the current protocol state.
     *
     * @return ProtocolState The Protocol state, an enum, where:
     *      0: Unpaused
     *      1: PublishingPaused
     *      2: Paused
     */
    function getState() external view returns (DataTypes.ProtocolState) {
        return _state;
    }
    ///设置状态
    function _setState(DataTypes.ProtocolState newState) internal {
        DataTypes.ProtocolState prevState = _state;
        _state = newState;
        emit Events.StateSet(msg.sender, prevState, newState, block.timestamp);
    }
    ///校验发布状态 
    function _validatePublishingEnabled() internal view {
        if (_state != DataTypes.ProtocolState.Unpaused) {
            revert Errors.PublishingPaused();
        }
    }
    ///校验没有暂停
    function _validateNotPaused() internal view {
        if (_state == DataTypes.ProtocolState.Paused) revert Errors.Paused();
    }
}
