// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Helpers} from './Helpers.sol';
import {DataTypes} from './DataTypes.sol';
import {Errors} from './Errors.sol';
import {Events} from './Events.sol';
import {Constants} from './Constants.sol';
import {IFollowModule} from '../interfaces/IFollowModule.sol';
import {ICollectModule} from '../interfaces/ICollectModule.sol';
import {IReferenceModule} from '../interfaces/IReferenceModule.sol';

/**
 * @title PublishingLogic
 * @author Lens Protocol
 *
 * @notice This is the library that contains the logic for profile creation & publication.
 * profile creation & publication 创建的逻辑库
 * @dev The functions are external, so they are called from the hub via `delegateCall` under the hood. Furthermore,
 * expected events are emitted from this library instead of from the hub to alleviate code size concerns.
 * 方法为external， 以便可以通过hub以 `delegateCall`调用。进一步说，期望的事件，将会emit，以减少hub关注代码量
 */
library PublishingLogic {
    /**
     * @notice Executes the logic to create a profile with the given parameters to the given address.
     * 以跟定的参数和地址，创建一个profile
     * @param vars The CreateProfileData struct containing the following parameters:
     *      to: The address receiving the profile.
     *      handle: The handle to set for the profile, must be unique and non-empty. //profile handle set
     *      imageURI: The URI to set for the profile image. // profile 图片URL
     *      followModule: The follow module to use, can be the zero address. follow模块
     *      followModuleInitData: The follow module initialization data, if any  follow模块初始化数据
     *      followNFTURI: The URI to set for the follow NFT. //follow NFT URL
     * @param profileId The profile ID to associate with this profile NFT (token ID). profile NFT Id
     * @param _profileIdByHandleHash The storage reference to the mapping of profile IDs by handle hash.   profile IDs hadle hash
     * @param _profileById The storage reference to the mapping of profile structs by IDs. 
     * @param _followModuleWhitelisted The storage reference to the mapping of whitelist status by follow module address.  follow的白名单
     */
    function createProfile(
        DataTypes.CreateProfileData calldata vars,
        uint256 profileId,
        mapping(bytes32 => uint256) storage _profileIdByHandleHash,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById,
        mapping(address => bool) storage _followModuleWhitelisted
    ) external {
        //校验处理器
        _validateHandle(vars.handle);
        //检查图片大小
        if (bytes(vars.imageURI).length > Constants.MAX_PROFILE_IMAGE_URI_LENGTH)
            revert Errors.ProfileImageURILengthInvalid();

        bytes32 handleHash = keccak256(bytes(vars.handle));
        //确保profile处理器hash不存在
        if (_profileIdByHandleHash[handleHash] != 0) revert Errors.HandleTaken();
        // 初始化profile数据DataTypes.ProfileStruct
        _profileIdByHandleHash[handleHash] = profileId;
        _profileById[profileId].handle = vars.handle;
        _profileById[profileId].imageURI = vars.imageURI;
        _profileById[profileId].followNFTURI = vars.followNFTURI;

        bytes memory followModuleReturnData;
        if (vars.followModule != address(0)) {
            _profileById[profileId].followModule = vars.followModule;
            //初始化follow 模块
            followModuleReturnData = _initFollowModule(
                profileId,
                vars.followModule,
                vars.followModuleInitData,
                _followModuleWhitelisted
            );
        }
        //创建Profile事件
        _emitProfileCreated(profileId, vars, followModuleReturnData);
    }

    /**
     * @notice Sets the follow module for a given profile.
     * 设置follow模块
     * @param profileId The profile ID to set the follow module for.
     * @param followModule The follow module to set for the given profile, if any.
     * @param followModuleInitData The data to pass to the follow module for profile initialization.
     * @param _profile The storage reference to the profile struct associated with the given profile ID.
     * @param _followModuleWhitelisted The storage reference to the mapping of whitelist status by follow module address.
     */
    function setFollowModule(
        uint256 profileId,
        address followModule,
        bytes calldata followModuleInitData,
        DataTypes.ProfileStruct storage _profile,
        mapping(address => bool) storage _followModuleWhitelisted
    ) external {
        if (followModule != _profile.followModule) {//确保模块变更
            _profile.followModule = followModule;
        }

        bytes memory followModuleReturnData;
        if (followModule != address(0))
             //初始化follow 模块
            followModuleReturnData = _initFollowModule(
                profileId,
                followModule,
                followModuleInitData,
                _followModuleWhitelisted
            );
        emit Events.FollowModuleSet(
            profileId,
            followModule,
            followModuleReturnData,
            block.timestamp
        );
    }

    /**
     * @notice Creates a post publication mapped to the given profile.
     * 创建publication
     * @dev To avoid a stack too deep error, reference parameters are passed in memory rather than calldata.
     *
     * @param profileId The profile ID to associate this publication to.
     * @param contentURI The URI to set for this publication.
     * @param collectModule The collect module to set for this publication.
     * @param collectModuleInitData The data to pass to the collect module for publication initialization.
     * @param referenceModule The reference module to set for this publication, if any.
     * @param referenceModuleInitData The data to pass to the reference module for publication initialization.
     * @param pubId The publication ID to associate with this publication.
     * @param _pubByIdByProfile The storage reference to the mapping of publications by publication ID by profile ID.
     * @param _collectModuleWhitelisted The storage reference to the mapping of whitelist status by collect module address.
     * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address.
     */
    function createPost(
        uint256 profileId,
        string memory contentURI,
        address collectModule,
        bytes memory collectModuleInitData,
        address referenceModule,
        bytes memory referenceModuleInitData,
        uint256 pubId,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        _pubByIdByProfile[profileId][pubId].contentURI = contentURI;

        // Collect module initialization 初始化collect
        bytes memory collectModuleReturnData = _initPubCollectModule(
            profileId,
            pubId,
            collectModule,
            collectModuleInitData,
            _pubByIdByProfile,
            _collectModuleWhitelisted
        );

        // Reference module initialization 初始化reference模块
        bytes memory referenceModuleReturnData = _initPubReferenceModule(
            profileId,
            pubId,
            referenceModule,
            referenceModuleInitData,
            _pubByIdByProfile,
            _referenceModuleWhitelisted
        );
        // post publication published 事件
        emit Events.PostCreated(
            profileId,
            pubId,
            contentURI,
            collectModule,
            collectModuleReturnData,
            referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }

    /**
     * @notice Creates a comment publication mapped to the given profile.
     * 创建评论
     * @dev This function is unique in that it requires many variables, so, unlike the other publishing functions,
     * we need to pass the full CommentData struct in memory to avoid a stack too deep error.
     *
     * @param vars The CommentData struct to use to create the comment.
     * @param pubId The publication ID to associate with this publication.
     * @param _profileById The storage reference to the mapping of profile structs by IDs.
     * @param _pubByIdByProfile The storage reference to the mapping of publications by publication ID by profile ID.
     * @param _collectModuleWhitelisted The storage reference to the mapping of whitelist status by collect module address.
     * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address.
     */
    function createComment(
        DataTypes.CommentData memory vars,
        uint256 pubId,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        // Validate existence of the pointed publication 确保检查publication
        uint256 pubCount = _profileById[vars.profileIdPointed].pubCount;
        if (pubCount < vars.pubIdPointed || vars.pubIdPointed == 0)
            revert Errors.PublicationDoesNotExist();

        // Ensure the pointed publication is not the comment being created  自己不允许评论自己
        if (vars.profileId == vars.profileIdPointed && vars.pubIdPointed == pubId)
            revert Errors.CannotCommentOnSelf();

        _pubByIdByProfile[vars.profileId][pubId].contentURI = vars.contentURI;
        _pubByIdByProfile[vars.profileId][pubId].profileIdPointed = vars.profileIdPointed;
        _pubByIdByProfile[vars.profileId][pubId].pubIdPointed = vars.pubIdPointed;

        // Collect Module Initialization //初始化PUBLIC collectModule
        bytes memory collectModuleReturnData = _initPubCollectModule(
            vars.profileId,
            pubId,
            vars.collectModule,
            vars.collectModuleInitData,
            _pubByIdByProfile,
            _collectModuleWhitelisted
        );

        // Reference module initialization //初始化profileId，pubId的referenceModule
        bytes memory referenceModuleReturnData = _initPubReferenceModule(
            vars.profileId,
            pubId,
            vars.referenceModule,
            vars.referenceModuleInitData,
            _pubByIdByProfile,
            _referenceModuleWhitelisted
        );

        // Reference module validation 
        address refModule = _pubByIdByProfile[vars.profileIdPointed][vars.pubIdPointed]
            .referenceModule;
        if (refModule != address(0)) {
            //IReferenceModule处理评论
            IReferenceModule(refModule).processComment(
                vars.profileId,
                vars.profileIdPointed,
                vars.pubIdPointed,
                vars.referenceModuleData
            );
        }

        // Prevents a stack too deep error 
        //创建评论事件
        _emitCommentCreated(vars, pubId, collectModuleReturnData, referenceModuleReturnData);
    }

    /**
     * @notice Creates a mirror publication mapped to the given profile.
     * 创建转发
     * @param vars The MirrorData struct to use to create the mirror.
     * @param pubId The publication ID to associate with this publication.
     * @param _pubByIdByProfile The storage reference to the mapping of publications by publication ID by profile ID.   publication ID 和 profile ID映射关系
     * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address. reference模块白名单
     */
    function createMirror(
        DataTypes.MirrorData memory vars,
        uint256 pubId,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        (uint256 rootProfileIdPointed, uint256 rootPubIdPointed, ) = Helpers.getPointedIfMirror(
            vars.profileIdPointed,
            vars.pubIdPointed,
            _pubByIdByProfile
        );
        //转发publications的原始profileId
        _pubByIdByProfile[vars.profileId][pubId].profileIdPointed = rootProfileIdPointed;
        //转发publications的原始PubI
        _pubByIdByProfile[vars.profileId][pubId].pubIdPointed = rootPubIdPointed;

        // Reference module initialization   //初始化profileId，pubId的referenceModule
        bytes memory referenceModuleReturnData = _initPubReferenceModule(
            vars.profileId,
            pubId,
            vars.referenceModule,
            vars.referenceModuleInitData,
            _pubByIdByProfile,
            _referenceModuleWhitelisted
        );

        // Reference module validation
        address refModule = _pubByIdByProfile[rootProfileIdPointed][rootPubIdPointed]
            .referenceModule;
        if (refModule != address(0)) {
            //IReferenceModule处理转发
            IReferenceModule(refModule).processMirror(
                vars.profileId,
                rootProfileIdPointed,
                rootPubIdPointed,
                vars.referenceModuleData
            );
        }
        //转发事件
        emit Events.MirrorCreated(
            vars.profileId,
            pubId,
            rootProfileIdPointed,
            rootPubIdPointed,
            vars.referenceModuleData,
            vars.referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }
    ///初始化PUBLIC collectModule
    function _initPubCollectModule(
        uint256 profileId,
        uint256 pubId,
        address collectModule,
        bytes memory collectModuleInitData,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted
    ) private returns (bytes memory) {
        if (!_collectModuleWhitelisted[collectModule]) revert Errors.CollectModuleNotWhitelisted();
        _pubByIdByProfile[profileId][pubId].collectModule = collectModule;
        return
            ICollectModule(collectModule).initializePublicationCollectModule(
                profileId,
                pubId,
                collectModuleInitData
            );
    }
    ///初始化profileId，pubId的referenceModule
    function _initPubReferenceModule(
        uint256 profileId,
        uint256 pubId,
        address referenceModule,
        bytes memory referenceModuleInitData,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) private returns (bytes memory) {
        if (referenceModule == address(0)) return new bytes(0);
        if (!_referenceModuleWhitelisted[referenceModule]) //确保为白名单
            revert Errors.ReferenceModuleNotWhitelisted();
        _pubByIdByProfile[profileId][pubId].referenceModule = referenceModule;
        return
            IReferenceModule(referenceModule).initializeReferenceModule(
                profileId,
                pubId,
                referenceModuleInitData
            );
    }
    /// 初始化关注数据
    function _initFollowModule(
        uint256 profileId,
        address followModule,
        bytes memory followModuleInitData,
        mapping(address => bool) storage _followModuleWhitelisted
    ) private returns (bytes memory) {
        //白名单检查
        if (!_followModuleWhitelisted[followModule]) revert Errors.FollowModuleNotWhitelisted();
        return IFollowModule(followModule).initializeFollowModule(profileId, followModuleInitData);
    }
    ///创建评论事件
    function _emitCommentCreated(
        DataTypes.CommentData memory vars,
        uint256 pubId,
        bytes memory collectModuleReturnData,
        bytes memory referenceModuleReturnData
    ) private {
        emit Events.CommentCreated(
            vars.profileId,
            pubId,
            vars.contentURI,
            vars.profileIdPointed,
            vars.pubIdPointed,
            vars.referenceModuleData,
            vars.collectModule,
            collectModuleReturnData,
            vars.referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }   
    ///创建Profile事件
    function _emitProfileCreated(
        uint256 profileId,
        DataTypes.CreateProfileData calldata vars,
        bytes memory followModuleReturnData
    ) internal {
        emit Events.ProfileCreated(
            profileId,
            msg.sender, // Creator is always the msg sender
            vars.to,
            vars.handle,
            vars.imageURI,
            vars.followModule,
            followModuleReturnData,
            vars.followNFTURI,
            block.timestamp
        );
    }
   ///校验处理器
    function _validateHandle(string calldata handle) private pure {
        bytes memory byteHandle = bytes(handle);
        if (byteHandle.length == 0 || byteHandle.length > Constants.MAX_HANDLE_LENGTH)
            revert Errors.HandleLengthInvalid();

        uint256 byteHandleLength = byteHandle.length;
        for (uint256 i = 0; i < byteHandleLength; ) {
            if (
                (byteHandle[i] < '0' ||
                    byteHandle[i] > 'z' ||
                    (byteHandle[i] > '9' && byteHandle[i] < 'a')) &&
                byteHandle[i] != '.' &&
                byteHandle[i] != '-' &&
                byteHandle[i] != '_'
            ) revert Errors.HandleContainsInvalidCharacters();
            unchecked {
                ++i;
            }
        }
    }
}
