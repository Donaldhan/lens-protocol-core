// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IFollowNFT} from '../interfaces/IFollowNFT.sol';
import {IFollowModule} from '../interfaces/IFollowModule.sol';
import {ILensHub} from '../interfaces/ILensHub.sol';
import {Errors} from '../libraries/Errors.sol';
import {Events} from '../libraries/Events.sol';
import {DataTypes} from '../libraries/DataTypes.sol';
import {Constants} from '../libraries/Constants.sol';
import {LensNFTBase} from './base/LensNFTBase.sol';

/**
 * @title FollowNFT
 * @author Lens Protocol
 *
 * @notice This contract is the NFT that is minted upon following a given profile. It is cloned upon first follow for a
 * given profile, and includes built-in governance power and delegation mechanisms.
 *
 * NOTE: This contract assumes total NFT supply for this follow NFT will never exceed 2^128 - 1
 */
contract FollowNFT is LensNFTBase, IFollowNFT {
    //快照
    struct Snapshot {
        uint128 blockNumber;
        uint128 value;
    }
   //hub 地址
    address public immutable HUB;
    //委托代理类型签名
    bytes32 internal constant DELEGATE_BY_SIG_TYPEHASH =
        keccak256(
            'DelegateBySig(address delegator,address delegatee,uint256 nonce,uint256 deadline)'
        );

    mapping(address => mapping(uint256 => Snapshot)) internal _snapshots;  //用户快照
    mapping(address => address) internal _delegates; //用户代理
    mapping(address => uint256) internal _snapshotCount;//用户快照计数器
    mapping(uint256 => Snapshot) internal _delSupplySnapshots;//总供应量
    uint256 internal _delSupplySnapshotCount;//总供应量快照索引
    uint256 internal _profileId; //profile
    uint256 internal _tokenIdCounter;//token计数器

    bool private _initialized;

    // We create the FollowNFT with the pre-computed HUB address before deploying the hub.
    constructor(address hub) {
        if (hub == address(0)) revert Errors.InitParamsInvalid();
        HUB = hub;
        _initialized = true;
    }

    /// @inheritdoc IFollowNFT
    function initialize(uint256 profileId) external override {
        if (_initialized) revert Errors.Initialized();
        _initialized = true;
        _profileId = profileId;
        emit Events.FollowNFTInitialized(profileId, block.timestamp);
    }

    /// @inheritdoc IFollowNFT 挖取
    function mint(address to) external override returns (uint256) {
        if (msg.sender != HUB) revert Errors.NotHub();
        unchecked {
            uint256 tokenId = ++_tokenIdCounter;
            _mint(to, tokenId);
            return tokenId;
        }
    }

    /// @inheritdoc IFollowNFT 代理
    function delegate(address delegatee) external override {
        _delegate(msg.sender, delegatee);
    }

    /// @inheritdoc IFollowNFT
    function delegateBySig(
        address delegator,
        address delegatee,
        DataTypes.EIP712Signature calldata sig
    ) external override {
        unchecked {
            _validateRecoveredAddress(
                _calculateDigest(
                    keccak256(
                        abi.encode(
                            DELEGATE_BY_SIG_TYPEHASH,
                            delegator,
                            delegatee,
                            sigNonces[delegator]++,
                            sig.deadline
                        )
                    )
                ),
                delegator,
                sig
            );
        }
        _delegate(delegator, delegatee);
    }

    /// @inheritdoc IFollowNFT 用户
    function getPowerByBlockNumber(address user, uint256 blockNumber)
        external
        view
        override
        returns (uint256)
    {
        if (blockNumber > block.number) revert Errors.BlockNumberInvalid();
        uint256 snapshotCount = _snapshotCount[user];
        if (snapshotCount == 0) return 0; // Returning zero since this means the user never delegated and has no power
        return _getSnapshotValueByBlockNumber(_snapshots[user], blockNumber, snapshotCount);
    }

    /// @inheritdoc IFollowNFT
    function getDelegatedSupplyByBlockNumber(uint256 blockNumber)
        external
        view
        override
        returns (uint256)
    {
        if (blockNumber > block.number) revert Errors.BlockNumberInvalid();
        uint256 snapshotCount = _delSupplySnapshotCount;
        if (snapshotCount == 0) return 0; // Returning zero since this means a delegation has never occurred
        return _getSnapshotValueByBlockNumber(_delSupplySnapshots, blockNumber, snapshotCount);
    }
    ///处理器
    function name() public view override returns (string memory) {
        string memory handle = ILensHub(HUB).getHandle(_profileId);
        return string(abi.encodePacked(handle, Constants.FOLLOW_NFT_NAME_SUFFIX));
    }

    function symbol() public view override returns (string memory) {
        string memory handle = ILensHub(HUB).getHandle(_profileId);
        bytes4 firstBytes = bytes4(bytes(handle));
        return string(abi.encodePacked(firstBytes, Constants.FOLLOW_NFT_SYMBOL_SUFFIX));
    }

    function _getSnapshotValueByBlockNumber(
        mapping(uint256 => Snapshot) storage _shots,
        uint256 blockNumber,
        uint256 snapshotCount
    ) internal view returns (uint256) {
        unchecked {
            uint256 lower = 0;
            uint256 upper = snapshotCount - 1;

            // First check most recent snapshot
            if (_shots[upper].blockNumber <= blockNumber) return _shots[upper].value;

            // Next check implicit zero balance
            if (_shots[lower].blockNumber > blockNumber) return 0;

            while (upper > lower) {
                uint256 center = upper - (upper - lower) / 2;
                Snapshot memory snapshot = _shots[center];
                if (snapshot.blockNumber == blockNumber) {
                    return snapshot.value;
                } else if (snapshot.blockNumber < blockNumber) {
                    lower = center;
                } else {
                    upper = center - 1;
                }
            }
            return _shots[lower].value;
        }
    }

    /**
     * @dev This returns the follow NFT URI fetched from the hub.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert Errors.TokenDoesNotExist();
        return ILensHub(HUB).getFollowNFTURI(_profileId);
    }

    /**
     * @dev Upon transfers, we move the appropriate delegations, and emit the transfer event in the hub.
     * 转移nft
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        address fromDelegatee = _delegates[from];
        address toDelegatee = _delegates[to];
        address followModule = ILensHub(HUB).getFollowModule(_profileId);
        //更新委托
        _moveDelegate(fromDelegatee, toDelegatee, 1);

        super._beforeTokenTransfer(from, to, tokenId);
        ILensHub(HUB).emitFollowNFTTransferEvent(_profileId, tokenId, from, to);
        if (followModule != address(0)) {
            //关注模块 hook
            IFollowModule(followModule).followModuleTransferHook(_profileId, from, to, tokenId);
        }
    }
    //委托代理
    function _delegate(address delegator, address delegatee) internal {
        //被代理者余额
        uint256 delegatorBalance = balanceOf(delegator);
        //先前代理者
        address previousDelegate = _delegates[delegator];
        _delegates[delegator] = delegatee;
        //移动代理权重
        _moveDelegate(previousDelegate, delegatee, delegatorBalance);
    }
    ///移动代理权重
     function _moveDelegate(
        address from,
        address to,
        uint256 amount
    ) internal {
        unchecked {
            bool fromZero = from == address(0);
            if (!fromZero) {
                //当前用户权重
                uint256 fromSnapshotCount = _snapshotCount[from];

                // Underflow is impossible since, if from != address(0), then a delegation must have occurred (at least 1 snapshot)
                uint256 previous = _snapshots[from][fromSnapshotCount - 1].value;
                uint128 newValue = uint128(previous - amount);
                //写新的快照
                _writeSnapshot(from, newValue, fromSnapshotCount);
                emit Events.FollowNFTDelegatedPowerChanged(from, newValue, block.timestamp);
            }
            //更为委托代理人的快照
            if (to != address(0)) {
                // if from == address(0) then this is an initial delegation (add amount to supply)
                // 初始化代理，添加供应量
                if (fromZero) {
                    // It is expected behavior that the `previousDelSupply` underflows upon the first delegation,
                    // returning the expected value of zero
                    uint256 delSupplySnapshotCount = _delSupplySnapshotCount;
                    uint128 previousDelSupply = _delSupplySnapshots[delSupplySnapshotCount - 1]
                        .value;
                    uint128 newDelSupply = uint128(previousDelSupply + amount);
                    //写新的供应量
                    _writeSupplySnapshot(newDelSupply, delSupplySnapshotCount);
                }

                // It is expected behavior that `previous` underflows upon the first delegation to an address,
                // returning the expected value of zero
                // 给委托者增加权限
                uint256 toSnapshotCount = _snapshotCount[to];
                uint128 previous = _snapshots[to][toSnapshotCount - 1].value;
                uint128 newValue = uint128(previous + amount);
                _writeSnapshot(to, newValue, toSnapshotCount);
                emit Events.FollowNFTDelegatedPowerChanged(to, newValue, block.timestamp);
            } else {
                // If from != address(0) then this is removing a delegation, otherwise we're dealing with a
                // non-delegated burn of tokens and don't need to take any action
                if (!fromZero) {//
                    // Upon removing delegation (from != address(0) && to == address(0)), supply calculations cannot
                    // underflow because if from != address(0), then a delegation must have previously occurred, so
                    // the snapshot count must be >= 1 and the previous delegated supply must be >= amount
                    uint256 delSupplySnapshotCount = _delSupplySnapshotCount;
                    uint128 previousDelSupply = _delSupplySnapshots[delSupplySnapshotCount - 1]
                        .value;
                    uint128 newDelSupply = uint128(previousDelSupply - amount);
                    _writeSupplySnapshot(newDelSupply, delSupplySnapshotCount);
                }
            }
        }
    }
    ///写用户权重快照
    function _writeSnapshot(
        address owner,
        uint128 newValue,
        uint256 ownerSnapshotCount
    ) internal {
        unchecked {
            uint128 currentBlock = uint128(block.number);
            mapping(uint256 => Snapshot) storage ownerSnapshots = _snapshots[owner];

            // Doing multiple operations in the same block
            if (
                ownerSnapshotCount != 0 &&
                ownerSnapshots[ownerSnapshotCount - 1].blockNumber == currentBlock
            ) { //同区块更新
                ownerSnapshots[ownerSnapshotCount - 1].value = newValue;
            } else {
                ownerSnapshots[ownerSnapshotCount] = Snapshot(currentBlock, newValue);
                _snapshotCount[owner] = ownerSnapshotCount + 1;
            }
        }
    }
    ///写新的供应量
    function _writeSupplySnapshot(uint128 newValue, uint256 supplySnapshotCount) internal {
        unchecked {
            uint128 currentBlock = uint128(block.number);

            // Doing multiple operations in the same block
            if (
                supplySnapshotCount != 0 &&
                _delSupplySnapshots[supplySnapshotCount - 1].blockNumber == currentBlock
            ) {//同区块更新
                _delSupplySnapshots[supplySnapshotCount - 1].value = newValue;
            } else {
                _delSupplySnapshots[supplySnapshotCount] = Snapshot(currentBlock, newValue);
                _delSupplySnapshotCount = supplySnapshotCount + 1;
            }
        }
    }
}
