// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ILensHub} from '../interfaces/ILensHub.sol';
import {Proxy} from '@openzeppelin/contracts/proxy/Proxy.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';

contract FollowNFTProxy is Proxy {
    using Address for address;
    address immutable HUB; //Hub地址

    constructor(bytes memory data) {
        HUB = msg.sender;
        //初始化FollowNFT functionDelegateCall？？？
        ILensHub(msg.sender).getFollowNFTImpl().functionDelegateCall(data);
    }
    //实现
    function _implementation() internal view override returns (address) {
        return ILensHub(HUB).getFollowNFTImpl();
    }
}
