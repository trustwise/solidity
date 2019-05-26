pragma solidity ^0.5.8;
pragma experimental ABIEncoderV2;

import "../ContractID.sol";
import "./Application.sol";
import "../SafeMath.sol";
import "./IConsortiumMembers.sol";
import "../Proxies/ConsortiumUpgradeabilityProxy.sol";

/**
 * @title Consortium members contract
 * @author Vladyslav Lupashevskyi
 * @dev This contract provides a multi-sig wallet features for consortium members
 * in order to operate with blockchain management related contracts, such as: validator,
 * peer manager, block reward, transaction permission, registry, certifier and ether receive
 * permission contracts. Set of allowed actions is defined in the contract initializer
 * and can be modified via specific actions. Each action is represented as action name key
 * and defines required percentage of votes to execute the action, the time-out for action
 * as well as functions which will be called on success, revoke or timeout.
 * In order to add new member, the address should be first invited, then submit application
 * and after all the application should be confirmed. Besides limited actions, consortium
 * can send ether to any address from this contract as well as upgrade the current contract.
 */
contract ConsortiumMembers is ContractID, IConsortiumMembers, Application {

    using SafeMath for uint256;

    /// Contract type and version

    /**
    * @dev Returns contract type.
    * @return Contract type.
    */
    function ContractType() public view returns(string memory) {
        return "CONSORTIUM";
    }

    /**
    * @dev Returns contract sub-type.
    * @return Contract sub-type.
    */
    function ContractSubType() public view returns(string memory) {
        return "MEMBERS_MULTI_SIG";
    }

    /**
    * @dev Returns contract version.
    * @return Contract version.
    */
    function ContractVersion() public view returns(uint256) {
        return 1;
    }

    event Submission(uint256 indexed transactionId);
    event Confirmation(address indexed member, uint256 indexed transactionId);
    event Revocation(address indexed member, uint256 indexed transactionId);
    event Execution(uint256 indexed transactionId, Statuses indexed status);

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event MemberLeft(address indexed member);

    event ActionAllowed(bytes32 action);
    event ActionDisallowed(bytes32 action);
    event ActionUpdated(bytes32 action);

    event Deposit(address indexed sender, uint256 value);

    enum Statuses {Submitted, Executed, Revoked, TimedOut}

    struct Action {
        uint256 requiredPercentage;  // If set to zero only one signature is required to perform transaction
        uint256 timeOut;  // If set to zero - no timeout
        address destination;
        // All functions should take the same arguments
        bytes4 successFunction;
        bytes4 revokeFunction;
        bytes4 timeOutFunction;
        // --------------------------------------------
        bool allowed;
    }

    struct Transaction {
        bytes32 action;
        uint256 value;
        bytes data; // Without fn selector
        bytes[] extraData;
    }

    address constant NULL_ADDRESS = 0x0000000000000000000000000000000000000000;

    /// Initialized flag
    bool initialized;

    /// Consortium members
    address[] members;
    mapping (address=>uint256) memberIndex;

    /// Mapping of allowed actions for consortium
    mapping (bytes32=>Action) public action;

    /// Pending, confirmed and rejected transactions
    mapping (uint256=>Transaction[]) transactions;
    /// Transaction status
    mapping (uint256=>Statuses) public transactionStatus;
    /// Transaction submission timestamp
    mapping (uint256=>uint256) public transactionSubmissionTimestamp;

    /// List of members who confirmed the transaction
    mapping (uint256=>address[]) confirmations;
    mapping (uint256=>mapping(address=>uint256)) confirmationIndex;

    /// List of members who revoked the transaction
    mapping (uint256=>address[]) revokes;
    mapping (uint256=>mapping(address=>uint256)) revokeIndex;

    /// Total amount of consortium transactions
    uint256 public transactionsLength;

    modifier notNull(address _address) {
        require (_address != NULL_ADDRESS, "Address should not be null-address");
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "Only self contract is allowed to execute this function");
        _;
    }

    modifier onlyMember() {
        require(isMember(msg.sender), "Only consortium member is allowed to execute this function");
        _;
    }

    /**
    * @dev Fallback function for accepting ether for this contract.
    */
    function() external payable {
        if (msg.value > 0)
            emit Deposit(msg.sender, msg.value);
    }

    /**
    * @dev Initializes contract with given blockchain management related contract addresses
    * and initial members
    * @param validator Validator contract address.
    * @param peerManager PeerManager contract address.
    * @param blockReward BlockReward contract address.
    * @param txPermission TxPermission contract address.
    * @param registry Registry contract address.
    * @param certifier Certifier contract address.
    * @param etherReceivePermission Ether receive permission contract address.
    * @param initialMembers List of initial consortium members.
    */
    function initialize(
        address validator,
        address peerManager,
        address blockReward,
        address txPermission,
        address registry,
        address certifier,
        address etherReceivePermission,
        address[] memory initialMembers
    ) public {
        require(!initialized, "Already initialized");
        for (uint256 i = 0; i < initialMembers.length; ++i) {
            _addMember(initialMembers[i]);
        }
        // CONSORTIUM MEMBERS
        action[keccak256("inviteMember")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: address(this),
            successFunction: bytes4(keccak256("invite(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("cancelInvitationMember")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: address(this),
            successFunction: bytes4(keccak256("cancelInvitation(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("processApplicationMember")] = Action ({
            requiredPercentage: 82,
            timeOut: 15 days,
            destination: address(this),
            successFunction: bytes4(keccak256("confirmApplication(address)")),
            revokeFunction: bytes4(keccak256("revokeApplication(address)")),
            timeOutFunction: bytes4(keccak256("revokeApplication(address)")),
            allowed: true
        });
        action[keccak256("removeMember")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: address(this),
            successFunction: bytes4(keccak256("removeMember(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowAction")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: address(this),
            successFunction: bytes4(keccak256("allowAction(bytes32,address,uint256,uint256,bytes4,bytes4,bytes4)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowAction")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: address(this),
            successFunction: bytes4(keccak256("disallowAction(bytes32)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("updateAction")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: address(this),
            successFunction: bytes4(keccak256("updateAction(bytes32,address,uint256,uint256,bytes4,bytes4,bytes4)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("upgradeTo")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: address(this),
            successFunction: bytes4(keccak256("upgradeTo(address,address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("upgradeToAndCall")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: address(this),
            successFunction: bytes4(keccak256("upgradeToAndCall(address,address,bytes)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        // VALIDATORS
        action[keccak256("inviteValidator")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: validator,
            successFunction: bytes4(keccak256("invite(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("cancelInvitationValidator")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: validator,
            successFunction: bytes4(keccak256("cancelInvitation(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("processApplicationValidator")] = Action ({
            requiredPercentage: 66,
            timeOut: 7 days,
            destination: validator,
            successFunction: bytes4(keccak256("confirmApplication(address)")),
            revokeFunction: bytes4(keccak256("revokeApplication(address)")),
            timeOutFunction: bytes4(keccak256("revokeApplication(address)")),
            allowed: true
        });
        action[keccak256("updateMaxValidators")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: validator,
            successFunction: bytes4(keccak256("updateMaxValidators(uint256)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("removeValidator")] = Action ({
            requiredPercentage: 51,
            timeOut: 7 days,
            destination: validator,
            successFunction: bytes4(keccak256("removeValidator(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        // ALLOWED PEERS
        action[keccak256("addPeerOwner")] = Action ({
            requiredPercentage: 17,
            timeOut: 3 days,
            destination: peerManager,
            successFunction: bytes4(keccak256("addPeerOwner(address,uint256)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("removePeerOwner")] = Action ({
            requiredPercentage: 66,
            timeOut: 7 days,
            destination: peerManager,
            successFunction: bytes4(keccak256("removePeerOwner(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("updateMaxAmountPeers")] = Action ({
            requiredPercentage: 66,
            timeOut: 7 days,
            destination: peerManager,
            successFunction: bytes4(keccak256("updateMaxAmount(address,uint256)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("addAdminPeer")] = Action ({
            requiredPercentage: 82,
            timeOut: 15 days,
            destination: peerManager,
            successFunction: bytes4(keccak256("addAdmin(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("removeAdminPeer")] = Action ({
            requiredPercentage: 82,
            timeOut: 15 days,
            destination: peerManager,
            successFunction: bytes4(keccak256("removeAdmin(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("enablePeerManager")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: peerManager,
            successFunction: bytes4(keccak256("enable()")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disablePeerManager")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: peerManager,
            successFunction: bytes4(keccak256("disable()")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        // BLOCK REWARD
        action[keccak256("updateBlockReward")] = Action ({
            requiredPercentage: 82,
            timeOut: 15 days,
            destination: blockReward,
            successFunction: bytes4(keccak256("updateBlockReward(uint256)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        // TX PERMISSION
        action[keccak256("addAdminTxPermission")] = Action ({
            requiredPercentage: 82,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("addAdmin(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("removeAdminTxPermission")] = Action ({
            requiredPercentage: 82,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("removeAdmin(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowFullTxPermissions")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: txPermission,
            successFunction: bytes4(keccak256("allowFullPermissions(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowFullTxPermissions")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disallowFullPermissions(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowToSendEtherToAnyAddress")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: txPermission,
            successFunction: bytes4(keccak256("allowToSendEtherToAnyAddress(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowToSendEtherToAnyAddress")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disallowToSendEtherToAnyAddress(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowTransferringEtherToSpecificAddresses")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: txPermission,
            successFunction: bytes4(keccak256("allowTransferringEtherToSpecificAddresses(address,address[])")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowTransferringEtherToSpecificAddresses")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disallowTransferringEtherToSpecificAddresses(address,address[])")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowContractCreation")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: txPermission,
            successFunction: bytes4(keccak256("allowContractCreation(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowContractCreation")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disallowContractCreation(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowCallToAnyAddress")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: txPermission,
            successFunction: bytes4(keccak256("allowCallToAnyAddress(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowCallToAnyAddress")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disallowCallToAnyAddress(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowCallToSpecificContractTypes")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: txPermission,
            successFunction: bytes4(keccak256("allowCallToSpecificContractTypes(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowCallToSpecificContractTypes")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disallowCallToSpecificContractTypes(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("setFilterByContractSubTypeTxPermission")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("setFilterByContractSubType(bool)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("setNotFilterByContractSubTypeForContractTypeTxPermission")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("setNotFilterByContractSubTypeForContractType(bytes32,bool)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowContractTypeTxPermission")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: txPermission,
            successFunction: bytes4(keccak256("allowContractType(bytes32)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowContractTypeTxPermission")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disallowContractType(bytes32)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("allowContractSubTypeTxPermission")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: txPermission,
            successFunction: bytes4(keccak256("allowContractSubType(bytes32,bytes32)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowContractSubTypeTxPermission")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disallowContractSubType(bytes32,bytes32)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("enableTxPermission")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("enable()")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disableTxPermission")] = Action ({
            requiredPercentage: 100,
            timeOut: 15 days,
            destination: txPermission,
            successFunction: bytes4(keccak256("disable()")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        // REGISTRY
        action[keccak256("allowRegistryPrefix")] = Action ({
            requiredPercentage: 0,
            timeOut: 0,
            destination: registry,
            successFunction: bytes4(keccak256("allowPrefix(address,string)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowRegistryPrefix")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: registry,
            successFunction: bytes4(keccak256("disallowPrefix(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("updateRegistryPrefix")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: registry,
            successFunction: bytes4(keccak256("updatePrefix(address,string)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("reserveName")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: registry,
            successFunction: bytes4(keccak256("reserve(bytes32,address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("confirmReverseAs")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: registry,
            successFunction: bytes4(keccak256("confirmReverseAs(string,address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        // CERTIFIER
        action[keccak256("certifyFreeTx")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: certifier,
            successFunction: bytes4(keccak256("certify(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("revokeFreeTxCertification")] = Action ({
            requiredPercentage: 66,
            timeOut: 15 days,
            destination: certifier,
            successFunction: bytes4(keccak256("revoke(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        // ETHER RECEIVE
        action[keccak256("allowReceiveEther")] = Action ({
            requiredPercentage: 51,
            timeOut: 5 days,
            destination: etherReceivePermission,
            successFunction: bytes4(keccak256("allow(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });
        action[keccak256("disallowReceiveEther")] = Action ({
            requiredPercentage: 51,
            timeOut: 5 days,
            destination: etherReceivePermission,
            successFunction: bytes4(keccak256("revoke(address)")),
            revokeFunction: 0,
            timeOutFunction: 0,
            allowed: true
        });

        initialized = true;
    }

    /**
     * @dev Submit transaction on behalf of the consortium. Allowed to be called by a consortium member.
     * It is possible to perform multiple actions in one call. Depending on the `confirm` argument
     * `confirmTransaction` or `revokeTransaction` function is called.
     * Length of `actions`, `values`, `data`, `extraData` arrays should be equal.
     * @param actions List of consortium actions to be performed in the transaction.
     * @param values List of values in wei to be transferred to the destination address of the action.
     * @param data List of data to be sent to the destination address of the action.
     * @param extraData List of extra data to be recorded it transaction.
     * @param confirm If true - `confirmTransaction` is called, otherwise `revokeTransaction` is called.
     * @return txTd ID of created transaction,
     */
    function submitTransaction(bytes32[] memory actions, uint256[] memory values, bytes[] memory data, bytes[][] memory extraData, bool confirm)
    public
    onlyMember
    returns (uint256 txId) {
        require(
            actions.length == values.length && values.length == data.length && data.length == extraData.length,
            "Arrays should have the same length"
        );
        require(actions.length > 0, "There should be at least one action");
        txId = transactionsLength;
        transactionsLength = transactionsLength.add(1);
        Transaction[] storage t = transactions[txId];
        transactionStatus[txId] = Statuses.Submitted;
        for (uint256 i = 0; i < actions.length; ++i) {
            t.push(
                Transaction({
                    action: actions[i],
                    value: values[i],
                    data: data[i],
                    extraData: extraData[i]
                })
            );
        }
        // solium-disable-next-line security/no-block-members
        transactionSubmissionTimestamp[txId] = now;
        emit Submission(txId);
        if (confirm) {
            confirmTransaction(txId);
        } else {
            revokeTransaction(txId);
        }
    }

    /**
     * @dev Confirm transaction. Allowed to be called by a consortium member.
     * Adds sender address to the list of confirmations.
     * Transaction status must be `Submitted`.
     * If sender has already revoked the transaction - the sender address
     * gets removed from list of revokes.
     * Calls `checkTransactionConditions` function.
     * @param txId Transaction ID.
     */
    function confirmTransaction(uint256 txId) public onlyMember {
        require(txHasStatus(txId, Statuses.Submitted), "Transaction should have status Submitted");
        if (hasRevoked(txId, msg.sender)) {
            _removeRevoke(txId, msg.sender);
        }
        _addConfirmation(txId, msg.sender);
        emit Confirmation(msg.sender, txId);
        checkTransactionConditions(txId);
    }

    /**
     * @dev Revoke transaction. Allowed to be called by a consortium member.
     * Adds sender address to the list of revokes.
     * Transaction status must be `Submitted`.
     * If sender has already confirmed the transaction - the sender address
     * gets removed from list of confirmation.
     * Calls `checkTransactionConditions` function.
     * @param txId Transaction ID.
     */
    function revokeTransaction(uint256 txId) public onlyMember {
        require(txHasStatus(txId, Statuses.Submitted), "Transaction should have status Submitted");
        if (hasConfirmed(txId, msg.sender)) {
            _removeConfirmation(txId, msg.sender);
        }
        _addRevoke(txId, msg.sender);
        emit Revocation(msg.sender, txId);
        checkTransactionConditions(txId);
    }

    /**
     * @dev Check transaction conditions. Allowed to be called by any address.
     * Checks timeout of transaction, if transaction is timed out - its status gets
     * assigned to `TimedOut`, otherwise the amount of confirmations is checked first and transaction
     * status becomes `Executed`, then the amount of revokes is checked.
     * In case when multiple actions are provided for transaction - the minimal amount and maximal
     * required percentage across all actions are taken for calculation.
     * The amount of sufficient confirmations is considered when:
     *   `confirmationsAmount * 100 >= membersAmount * maxPercentage`.
     * The amount of sufficient revokes is considered when:
     *   `revokesAmount * 100 >= membersAmount * (100 - maxPercentage)`.
     * Depending on assigned status `successFunction`, `revokeFunction` or `timeOutFunction`
     * is called for each action with provided data.
     * The data provided in the call is represented as: `functionSelector . data`.
     * @param txId Transaction ID.
     */
    function checkTransactionConditions(uint256 txId) public {
        Transaction[] storage t = transactions[txId];
        uint256 minTimeOut = action[t[0].action].timeOut;
        uint256 maxPercentage = action[t[0].action].requiredPercentage;
        for (uint256 i = 0; i < t.length; ++i) {
            require(action[t[i].action].allowed, "Action is not allowed");
            if (action[t[i].action].timeOut < minTimeOut) {
                minTimeOut = action[t[i].action].timeOut;
            }
            if (action[t[i].action].requiredPercentage > maxPercentage) {
                maxPercentage = action[t[i].action].requiredPercentage;
            }
        }
        if (!txHasStatus(txId, Statuses.Submitted)) {
            return;
        }
        // solium-disable-next-line security/no-block-members
        if ((minTimeOut > 0) && (now > (transactionSubmissionTimestamp[txId].add(minTimeOut)))) {
            transactionStatus[txId] = Statuses.TimedOut;
            for (uint256 i = 0; i < t.length; ++i) {
                bytes4 fnSelector = action[t[i].action].timeOutFunction;
                if (fnSelector == 0x0) continue;
                bytes memory data = abi.encodePacked(
                    fnSelector,
                    t[i].data
                );
                _executeTransaction(action[t[i].action].destination, t[i].value, data);
                emit Execution(txId, transactionStatus[txId]);
            }
        } else if ((confirmations[txId].length > 0) && (confirmations[txId].length.mul(100) >= members.length.mul(maxPercentage))) {
            transactionStatus[txId] = Statuses.Executed;
            for (uint256 i = 0; i < t.length; ++i) {
                bytes4 fnSelector = action[t[i].action].successFunction;
                if (fnSelector == 0x0) continue;
                bytes memory data = abi.encodePacked(
                    fnSelector,
                    t[i].data
                );
                _executeTransaction(action[t[i].action].destination, t[i].value, data);
                emit Execution(txId, transactionStatus[txId]);
            }
        } else if ((revokes[txId].length > 0) && (revokes[txId].length.mul(100) >= members.length.mul(100 - maxPercentage))) {
            transactionStatus[txId] = Statuses.Revoked;
            for (uint256 i = 0; i < t.length; ++i) {
                bytes4 fnSelector = action[t[i].action].revokeFunction;
                if (fnSelector == 0x0) continue;
                bytes memory data = abi.encodePacked(
                    fnSelector,
                    t[i].data
                );
                _executeTransaction(action[t[i].action].destination, t[i].value, data);
                emit Execution(txId, transactionStatus[txId]);
            }
        }
    }

    /** @dev Remove consortium member.
     * Allowed to call only from self address (action should be performed via voting).
     * Last consortium member cannot be removed.
     * @param member Address of the consortium member to be removed.
     */
    function removeMember(address member) public onlySelf {
        require(members.length > 1, "Cannot remove the last consortium member");
        _removeMember(member);
        emit MemberRemoved(member);
    }

    /**
     * @dev Leave from consortium.
     * Allows for consortium member to remove member's address from the list.
     * The action cannot be performed when there is only one consortium member.
     */
    function leave() public onlyMember {
        require(members.length > 1, "The last consortium member cannot leave");
        _removeMember(msg.sender);
        emit MemberLeft(msg.sender);
    }

    /**
     * @dev Allow action to be executed by consortium.
     * @param newAction Action hash.
     * @param destination Destination address for action which is called when transaction is executed.
     * @param requiredPercentage Required percentage of consortium member confirmations for transaction execution.
     * @param timeOut Timeout for action.
     * @param successFunction Selector of function to be called at destination when transaction gets confirmed.
     * @param revokeFunction Selector of function to be called at destination when transaction gets revoked.
     * @param timeOutFunction Selector of function to be called at destination when transaction is timed out.
     */
    function allowAction(
        bytes32 newAction,
        address destination,
        uint256 requiredPercentage,
        uint256 timeOut,
        bytes4 successFunction,
        bytes4 revokeFunction,
        bytes4 timeOutFunction
    ) public onlySelf {
        require(!action[newAction].allowed, "Action is already allowed");
        require(requiredPercentage <= 100, "Percentage cannot be greater than 100%");
        action[newAction] = Action({
            destination: destination,
            requiredPercentage: requiredPercentage,
            timeOut: timeOut,
            successFunction: successFunction,
            revokeFunction: revokeFunction,
            timeOutFunction: timeOutFunction,
            allowed: true
        });
        emit ActionAllowed(newAction);
    }

    /**
     * @dev Disallow action for consortium.
     * Resets all action parameters to default values.
     * Service actions such as `allowAction`, `disallowAction` and `updateAction` cannot be disallowed.
     * @param _action Action hash.
     */
    function disallowAction(bytes32 _action) public {
        require(action[_action].allowed, "Action is not allowed");
        require(_action != keccak256("allowAction"), "Cannot disallow service functions");
        require(_action != keccak256("disallowAction"), "Cannot disallow service functions");
        require(_action != keccak256("updateAction"), "Cannot disallow service functions");
        Action storage a = action[_action];
        a.allowed = false;
        a.destination = NULL_ADDRESS;
        a.requiredPercentage = 0;
        a.timeOut = 0;
        a.successFunction = 0;
        a.revokeFunction = 0;
        a.timeOutFunction = 0;
        emit ActionDisallowed(_action);
    }

    /**
     * @dev Update existing action parameters.
     * @param _action Action hash.
     * @param destination Destination address for action which is called when transaction is executed.
     * @param requiredPercentage Required percentage of consortium member confirmations for transaction execution.
     * @param timeOut Timeout for action.
     * @param successFunction Selector of function to be called at destination when transaction gets confirmed.
     * @param revokeFunction Selector of function to be called at destination when transaction gets revoked.
     * @param timeOutFunction Selector of function to be called at destination when transaction is timed out.
     */
    function updateAction(
        bytes32 _action,
        address destination,
        uint256 requiredPercentage,
        uint256 timeOut,
        bytes4 successFunction,
        bytes4 revokeFunction,
        bytes4 timeOutFunction
    ) public onlySelf {
        require(action[_action].allowed, "Action is not allowed");
        require(requiredPercentage <= 100, "Percentage cannot be greater than 100%");
        action[_action] = Action({
            destination: destination,
            requiredPercentage: requiredPercentage,
            timeOut: timeOut,
            successFunction: successFunction,
            revokeFunction: revokeFunction,
            timeOutFunction: timeOutFunction,
            allowed: true
        });
        emit ActionUpdated(_action);
    }

    /**
     * @dev Send ether from consortium contract address.
     * Allowed to call only from self address (action should be performed via voting).
     * @param destination Ether recipient address
     * @param value Amount in wei to be transferred to destination address
     */
    function sendEther(address payable destination, uint256 value) public onlySelf {
        destination.transfer(value);
    }

    /**
     * @dev Upgrade the backing implementation of the blockchain management related contract proxy.
     * Executes `upgradeTo(address)` function on `_contract`.
     * @param _contract Address of the proxy contract to be upgraded.
     * @param newImplementation Address of the new implementation.
     */
    function upgradeTo(address _contract, address newImplementation) external onlySelf {
        ConsortiumUpgradeabilityProxy(address(uint160(_contract))).upgradeTo(newImplementation);
    }

    /**
     * @dev Upgrade the backing implementation of the blockchain management related contract proxy.
     * Calls the function on the new implementation.
     * Executes `upgradeTo(address)` function on `_contract`.
     * @param _contract Address of the proxy contract to be upgraded.
     * @param data Data to send as msg.data in the low level call.
     * It should include the signature and the parameters of the function to be
     * called, as described in
     * https://solidity.readthedocs.io/en/develop/abi-spec.html#function-selector-and-argument-encoding.
     * @param newImplementation Address of the new implementation.
     */
    function upgradeToAndCall(address _contract, address newImplementation, bytes calldata data) external payable onlySelf {
        ConsortiumUpgradeabilityProxy(address(uint160(_contract))).upgradeToAndCall(newImplementation, data);
    }

    /**
     * @dev Get consortium member addresses list.
     * @return Consortium member addresses list.
     */
    function getMembers() external view returns(address[] memory) {
        return members;
    }

    /**
     * @dev Get transaction details for specified range of transaction IDs.
     * @param from First transaction ID.
     * @param to Last transaction ID (incl.).
     * @return _transactions Array of `Transaction` structures.
     * @return _statuses Transaction statuses.
     * @return _confirmations Transaction confirmations.
     * @return _revokes Transaction revokes.
     */
    function getTransactionDetails(uint256 from, uint256 to) external view returns (
        Transaction[][] memory _transactions,
        Statuses[] memory _statuses,
        uint256[] memory _submissionTimestamps,
        address[][] memory _confirmations,
        address[][] memory _revokes
    ) {
        require(to >= from, "Incorrect to/from parameters");
        require(txExists(to), "Requesting non-existing transaction");
        uint256 len = to - from + 1;
        _transactions = new Transaction[][](len);
        _statuses = new Statuses[](len);
        _submissionTimestamps = new uint256[](len);
        _confirmations = new address[][](len);
        _revokes = new address[][](len);
        uint256 c = 0;
        for (uint256 i = from; i <= to; ++i) {
            _transactions[c] = transactions[i];
            _statuses[c] = transactionStatus[i];
            _submissionTimestamps[c] = transactionSubmissionTimestamp[i];
            _confirmations[c] = confirmations[i];
            _revokes[c] = revokes[i];
            c = c.add(1);
        }
    }

    /**
     * @dev Get transaction details from `Transaction` structure for specified range of transaction IDs.
     * @param from First transaction ID.
     * @param to Last transaction ID (incl.).
     * @return _actions Transaction actions.
     * @return _values Transaction values in wei.
     * @return _data Transaction data (without function selector).
     * @return _extraData Transaction extra data.
     */
    function getTransactions(uint256 from, uint256 to) external view returns (
        bytes32[][] memory _actions,
        uint256[][] memory _values,
        bytes[][] memory _data,
        bytes[][][] memory _extraData
    ) {
        require(to >= from, "Incorrect to/from parameters");
        require(txExists(to), "Requesting non-existing transaction");
        uint256 len = to - from + 1;
        _actions = new bytes32[][](len);
        _values = new uint256[][](len);
        _data = new bytes[][](len);
        _extraData = new bytes[][][](len);
        uint256 c = 0;
        for (uint256 i = from; i <= to; ++i) {
            uint256 subLen = transactions[i].length;
            _actions[c] = new bytes32[](subLen);
            _values[c] = new uint256[](subLen);
            _data[c] = new bytes[](subLen);
            _extraData[c] = new bytes[][](subLen);
            for (uint j = 0; j < subLen; ++j) {
                _actions[c][j] = transactions[i][j].action;
                _values[c][j] = transactions[i][j].value;
                _data[c][j] = transactions[i][j].data;
                _extraData[c][j] = transactions[i][j].extraData;
            }
            c = c.add(1);
        }
    }

    /**
     * @dev Get transaction confirmations for specified range of transaction IDs.
     * @param from First transaction ID.
     * @param to Last transaction ID (incl.).
     * @return _confirmations Transaction confirmations.
     */
    function getConfirmations(uint256 from, uint256 to) external view returns (address[][] memory _confirmations) {
        require(to >= from, "Incorrect to/from parameters");
        require(txExists(to), "Requesting non-existing transaction");
        uint256 len = to - from + 1;
        _confirmations = new address[][](len);
        uint256 c = 0;
        for (uint256 i = from; i <= to; ++i) {
            _confirmations[c] = confirmations[i];
            c = c.add(1);
        }
    }

    /**
     * @dev Get transaction revokes for specified range of transaction IDs.
     * @param from First transaction ID.
     * @param to Last transaction ID (incl.).
     * @return _revokes Transaction revokes.
     */
    function getRevokes(uint256 from, uint256 to) external view returns (address[][] memory _revokes) {
        require(to >= from, "Incorrect to/from parameters");
        require(txExists(to), "Requesting non-existing transaction");
        uint256 len = to - from + 1;
        _revokes = new address[][](len);
        uint256 c = 0;
        for (uint256 i = from; i <= to; ++i) {
            _revokes[c] = revokes[i];
            c = c.add(1);
        }
    }

    /**
     * @dev Get transaction statuses for specified range of transaction IDs.
     * @param from First transaction ID.
     * @param to Last transaction ID (incl.).
     * @return _statuses Transaction statuses.
     */
    function getTransactionStatuses(uint256 from, uint256 to) external view returns (uint8[] memory _statuses) {
        require(to >= from, "Incorrect to/from parameters");
        require(txExists(to), "Requesting non-existing transaction");
        uint256 len = to - from + 1;
        _statuses = new uint8[](len);
        uint256 c = 0;
        for (uint256 i = from; i <= to; ++i) {
            _statuses[c] = uint8(transactionStatus[i]);
            c = c.add(1);
        }
    }

    /**
     * @dev Get transaction submission timestamps for specified range of transaction IDs.
     * @param from First transaction ID.
     * @param to Last transaction ID (incl.).
     * @return _statuses Transaction submission timestamps.
     */
    function getTransactionSubmissionTimestamps(uint256 from, uint256 to) external view returns (uint256[] memory _timestamps) {
        require(to >= from, "Incorrect to/from parameters");
        require(txExists(to), "Requesting non-existing transaction");
        uint256 len = to - from + 1;
        _timestamps = new uint256[](len);
        uint256 c = 0;
        for (uint256 i = from; i <= to; ++i) {
            _timestamps[c] = transactionSubmissionTimestamp[i];
            c = c.add(1);
        }
    }

    /**
     * @dev Check whether transaction exists.
     * @param txId Transaction ID.
     * @return True if transaction with given ID exists.
     */
    function txExists(uint256 txId) public view returns (bool) {
        return txId < transactionsLength;
    }

    /**
     * @dev Check transaction status.
     * @param txId Transaction ID.
     * @param status Transaction status to be checked against.
     * @return True if transaction with given ID status equals `status`.
     */
    function txHasStatus(uint256 txId, Statuses status) public view returns(bool) {
        require(txExists(txId), "Transaction does not exist");
        return transactionStatus[txId] == status;
    }

    /**
     * @dev Check whether address is consortium member.
     * @param _address Address to be checked.
     * @return True if given address is consortium member.
     */
    function isMember(address _address) public view returns(bool) {
        if (members.length == 0) return false;
        return members[memberIndex[_address]] == _address;
    }

    /**
     * @dev Check if the address has confirmed transaction.
     * @param txId Transaction ID.
     * @param _address Consortium member address to be checked.
     * @return True if given address has confirmed the transaction with given ID.
     */
    function hasConfirmed(uint256 txId, address _address) public view returns(bool) {
        if (confirmations[txId].length == 0) return false;
        return confirmations[txId][confirmationIndex[txId][_address]] == _address;
    }

    /**
     * @dev Check if the address has revoked transaction.
     * @param txId Transaction ID.
     * @param _address Consortium member address to be checked.
     * @return True if given address has revoked the transaction with given ID.
     */
    function hasRevoked(uint256 txId, address _address) public view returns(bool) {
        if (revokes[txId].length == 0) return false;
        return revokes[txId][revokeIndex[txId][_address]] == _address;
    }

    /**
     * @dev Helper function for adding consortium member to the members list.
     * @param member Address of the member to be added.
     */
    function _addMember(address member) internal notNull(member) {
        require(!isMember(member), "Current member already exists");
        memberIndex[member] = members.push(member) - 1;
    }

    /**
     * @dev Helper function for removing consortium member from the members list.
     * @param member Address of the member to be removed.
     */
    function _removeMember(address member) internal {
        require(isMember(member), "Member address does not exist");
        uint256 indexToRemove = memberIndex[member];
        address addressToMove = members[members.length - 1];
        members[indexToRemove] = addressToMove;
        memberIndex[addressToMove] = indexToRemove;
        memberIndex[member] = 0;
        members.length--;
    }

    /**
     * @dev Helper function for adding consortium member address to the transaction confirmations list.
     * @param txId Transaction ID
     * @param member Address of the member to be added to the confirmations list.
     */
    function _addConfirmation(uint256 txId, address member) internal notNull(member) {
        require(!hasConfirmed(txId, member), "Already confirmed");
        confirmationIndex[txId][member] = confirmations[txId].push(member) - 1;
    }

    /**
     * @dev Helper function for removing consortium member address from the transaction confirmations list.
     * @param txId Transaction ID
     * @param member Address of the member to be removed from the confirmations list.
     */
    function _removeConfirmation(uint256 txId, address member) internal {
        require(hasConfirmed(txId, member), "Not confirmed");
        uint256 indexToRemove = confirmationIndex[txId][member];
        address addressToMove = confirmations[txId][confirmations[txId].length - 1];
        confirmations[txId][indexToRemove] = addressToMove;
        confirmationIndex[txId][addressToMove] = indexToRemove;
        confirmationIndex[txId][member] = 0;
        confirmations[txId].length--;
    }

    /**
     * @dev Helper function for adding consortium member address to the transaction revokes list.
     * @param txId Transaction ID
     * @param member Address of the member to be added to the revokes list.
     */
    function _addRevoke(uint256 txId, address member) internal notNull(member) {
        require(!hasRevoked(txId, member), "Already revoked");
        revokeIndex[txId][member] = revokes[txId].push(member) - 1;
    }

    /**
     * @dev Helper function for removing consortium member address from the transaction revokes list.
     * @param txId Transaction ID
     * @param member Address of the member to be removed from the revokes list.
     */
    function _removeRevoke(uint256 txId, address member) internal {
        require(hasRevoked(txId, member), "Not revoked");
        uint256 indexToRemove = revokeIndex[txId][member];
        address addressToMove = revokes[txId][revokes[txId].length - 1];
        revokes[txId][indexToRemove] = addressToMove;
        revokeIndex[txId][addressToMove] = indexToRemove;
        revokeIndex[txId][member] = 0;
        revokes[txId].length--;
    }

    /**
     * @dev Helper function for adding consortium member to the members list.
     * Emits MemberAdded event.
     * @param member Address of the member to be added.
     */
    function addMember(address member) internal {
        _addMember(member);
        emit MemberAdded(member);
    }

    /**
     * @dev Implementation of the abstract function `canManage(address)` for Application contract.
     * Defines that only self address is able to manage consortium membership applications.
     * @param sender Message sender address.
     */
    function canManage(address sender) internal {
        require(sender == address(this), "Only ConsortiumMembers contract is allowed to execute this function");
    }

    /**
     * @dev Implementation of the abstract function `canBeInvited(address)` for Application contract.
     * Defines that it's not allowed to invite existing consortium members.
     * @param invitee Invitee address.
     */
    function canBeInvited(address invitee) internal view returns(bool) {
        return !isMember(invitee);
    }

    /**
     * @dev Implementation of the abstract function `onApplicationConfirmed(address)` for Application contract.
     * Defines that when membership application is confirmed the applicant gets added to
     * consortium members list.
     * @param invitee Invitee address.
     */
    function onApplicationConfirmed(address member) internal {
        addMember(member);
    }

    /**
     * @dev Helper function for execution transaction on behalf of self contract.
     * Propagates the return data (revert data as well) from call.
     * @param destination Call destination address.
     * @param value Value in wei to be transferred to the destination.
     * @param data Data to be sent to the destination.
     */
    function _executeTransaction(address destination, uint256 value, bytes memory data) internal {
        // solium-disable-next-line security/no-call-value, no-unused-vars
        (bool result,) = destination.call.value(value)(data);
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let returnsize := returndatasize
            let ptr := mload(0x40)
            returndatacopy(ptr, 0, returnsize)
            switch result
                case 0 {
                    revert(ptr, returnsize)
                }
                default {
                    return(ptr, returnsize)
                }
        }
    }
}
