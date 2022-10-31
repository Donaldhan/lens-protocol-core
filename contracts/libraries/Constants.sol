// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

library Constants {
    string internal constant FOLLOW_NFT_NAME_SUFFIX = '-Follower';// Follower NFT后缀
    string internal constant FOLLOW_NFT_SYMBOL_SUFFIX = '-Fl';//Follower NFT 符号后缀
    string internal constant COLLECT_NFT_NAME_INFIX = '-Collect-';// COLLECT NFT后缀
    string internal constant COLLECT_NFT_SYMBOL_INFIX = '-Cl-';//COLLECT NFT 符号后缀
    uint8 internal constant MAX_HANDLE_LENGTH = 31;//HANDLE 最大长度
    uint16 internal constant MAX_PROFILE_IMAGE_URI_LENGTH = 6000;//PROFILE图片长度
}
