// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

// solhint-disable no-unused-vars

// ============ Internal Imports ============
import {Message} from "../external/hyperlane/libs/Message.sol";
import {TypeCasts} from "../external/hyperlane/libs/TypeCasts.sol";
import {IInterchainSecurityModule} from "../external/hyperlane/interfaces/IInterchainSecurityModule.sol";
import {IPostDispatchHook} from "../external/hyperlane/interfaces/hooks/IPostDispatchHook.sol";
import {IMessageRecipient} from "../external/hyperlane//interfaces/IMessageRecipient.sol";
import {IMailbox} from "../external/hyperlane/interfaces/IMailbox.sol";

// ============ External Imports ============
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Mailbox is IMailbox, Ownable {
    uint8 public constant VERSION = 33;

    // ============ Libraries ============

    using Message for bytes;
    using TypeCasts for bytes32;
    using TypeCasts for address;

    // ============ Constants ============

    // Domain of chain on which the contract is deployed
    uint32 public localDomain;

    // TEST - static fee
    uint256 public hardcodedFee;

    // ============ Public Storage ============

    // A monotonically increasing nonce for outbound unique message IDs.
    uint32 public nonce;

    // The latest dispatched message ID used for auth in post-dispatch hooks.
    bytes32 public latestDispatchedId;

    // The default ISM, used if the recipient fails to specify one.
    IInterchainSecurityModule public defaultIsm;

    // The default post dispatch hook, used for post processing of opting-in dispatches.
    IPostDispatchHook public defaultHook;

    // The required post dispatch hook, used for post processing of ALL dispatches.
    IPostDispatchHook public requiredHook;

    // Mapping of message ID to delivery context that processed the message.
    struct Delivery {
        address processor;
        uint48 blockNumber;
    }

    mapping(bytes32 => Delivery) internal deliveries;

    // ============ Error ============

    error DispatchUnderpaid();

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {
        localDomain = 123;
        hardcodedFee = 0.01 ether;
        defaultHook = IPostDispatchHook(address(0));
    }

    // ============ External Functions ============
    /**
     * @notice Dispatches a message to the destination domain & recipient
     * @param _destinationDomain Domain of destination chain
     * @param _recipientAddress Address of recipient on destination chain as bytes32
     * @param _messageBody Raw bytes content of message body
     * @return The message ID inserted into the Mailbox's merkle tree
     */
    function dispatch(
        uint32 _destinationDomain,
        bytes32 _recipientAddress,
        bytes calldata _messageBody
    ) external payable override returns (bytes32) {
        return
            dispatch(
                _destinationDomain,
                _recipientAddress,
                _messageBody,
                _messageBody[0:0],
                defaultHook
            );
    }

    /**
     * @notice Dispatches a message to the destination domain & recipient.
     * @param destinationDomain Domain of destination chain
     * @param recipientAddress Address of recipient on destination chain as bytes32
     * @param messageBody Raw bytes content of message body
     * @param hookMetadata Metadata used by the post dispatch hook
     * @return The message ID inserted into the Mailbox's merkle tree
     */
    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata hookMetadata
    ) external payable override returns (bytes32) {
        return
            dispatch(
                destinationDomain,
                recipientAddress,
                messageBody,
                hookMetadata,
                defaultHook
            );
    }

    /**
     * @notice Computes quote for dipatching a message to the destination domain & recipient
     * using the default hook and empty metadata.
     * @param destinationDomain Domain of destination chain
     * @param recipientAddress Address of recipient on destination chain as bytes32
     * @param messageBody Raw bytes content of message body
     * @return fee The payment required to dispatch the message
     */
    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external view returns (uint256 fee) {
        return
            quoteDispatch(
                destinationDomain,
                recipientAddress,
                messageBody,
                messageBody[0:0],
                defaultHook
            );
    }

    /**
     * @notice Computes quote for dispatching a message to the destination domain & recipient.
     * @param destinationDomain Domain of destination chain
     * @param recipientAddress Address of recipient on destination chain as bytes32
     * @param messageBody Raw bytes content of message body
     * @param defaultHookMetadata Metadata used by the default post dispatch hook
     * @return fee The payment required to dispatch the message
     */
    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata defaultHookMetadata
    ) external view returns (uint256 fee) {
        return
            quoteDispatch(
                destinationDomain,
                recipientAddress,
                messageBody,
                defaultHookMetadata,
                defaultHook
            );
    }

    /**
     * @notice Attempts to deliver `_message` to its recipient. Verifies
     * `_message` via the recipient's ISM using the provided `_metadata`.
     * @param _message Formatted Hyperlane message (refer to Message.sol).
     */
    function process(
        bytes calldata /* _metadata */,
        bytes calldata _message
    ) external payable override {
        /// CHECKS ///

        // Check that the message was intended for this mailbox.
        require(_message.version() == VERSION, "Mailbox: bad version");
        require(
            _message.destination() == localDomain,
            "Mailbox: unexpected destination"
        );

        // Check that the message hasn't already been delivered.
        bytes32 _id = _message.id();
        require(delivered(_id) == false, "Mailbox: already delivered");

        // Get the recipient's ISM.
        address recipient = _message.recipientAddress();

        /// EFFECTS ///

        deliveries[_id] = Delivery({
            processor: msg.sender,
            blockNumber: uint48(block.number)
        });
        emit Process(_message.origin(), _message.sender(), recipient);
        emit ProcessId(_id);

        /// INTERACTIONS ///

        // Deliver the message to the recipient.
        IMessageRecipient(recipient).handle{value: msg.value}(
            _message.origin(),
            _message.sender(),
            _message.body()
        );
    }

    /**
     * @notice Returns the account that processed the message.
     * @param _id The message ID to check.
     * @return The account that processed the message.
     */
    function processor(bytes32 _id) external view returns (address) {
        return deliveries[_id].processor;
    }

    /**
     * @notice Returns the account that processed the message.
     * @param _id The message ID to check.
     * @return The number of the block that the message was processed at.
     */
    function processedAt(bytes32 _id) external view returns (uint48) {
        return deliveries[_id].blockNumber;
    }

    // ============ Public Functions ============

    /**
     * @notice Dispatches a message to the destination domain & recipient.
     * @param destinationDomain Domain of destination chain
     * @param recipientAddress Address of recipient on destination chain as bytes32
     * @param messageBody Raw bytes content of message body
     * @param metadata Metadata used by the post dispatch hook
     * @return The message ID inserted into the Mailbox's merkle tree
     */
    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata metadata,
        IPostDispatchHook /* hook */
    ) public payable virtual returns (bytes32) {
        /// CHECKS ///

        // Format the message into packed bytes.
        bytes memory message = _buildMessage(
            destinationDomain,
            recipientAddress,
            messageBody
        );
        bytes32 id = message.id();

        /// EFFECTS ///

        latestDispatchedId = id;
        nonce += 1;
        emit Dispatch(msg.sender, destinationDomain, recipientAddress, message);
        emit DispatchId(id);

        /// INTERACTIONS ///
        uint256 requiredValue = this.quoteDispatch(destinationDomain, recipientAddress, message);
        // if underpaying, throw error
        if (msg.value < requiredValue) {
            revert DispatchUnderpaid();
        }

        // TEST - execute process in the same transaction
        this.process(metadata, message);

        return id;
    }

    /**
     * @notice Computes quote for dispatching a message to the destination domain & recipient.
     * @return fee The payment required to dispatch the message
     */
    function quoteDispatch(
        uint32 /* destinationDomain */,
        bytes32 /* recipientAddress */,
        bytes calldata /* messageBody */,
        bytes calldata /* metadata */,
        IPostDispatchHook /* hook */
    ) public view returns (uint256 fee) {
        return hardcodedFee;
    }

    /**
     * @notice Returns true if the message has been processed.
     * @param _id The message ID to check.
     * @return True if the message has been delivered.
     */
    function delivered(bytes32 _id) public view override returns (bool) {
        return deliveries[_id].blockNumber > 0;
    }

    /**
     * @notice Returns the ISM to use for the recipient, defaulting to the
     * default ISM if none is specified.
     * @return The ISM to use for `_recipient`.
     */
    function recipientIsm(
        address /* _recipient */
    ) public view returns (IInterchainSecurityModule) {
        return defaultIsm;
    }

    // ============ Internal Functions ============
    function _buildMessage(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) internal view returns (bytes memory) {
        return
            Message.formatMessage(
                VERSION,
                nonce,
                localDomain,
                msg.sender.addressToBytes32(),
                destinationDomain,
                recipientAddress,
                messageBody
            );
    }
}
