// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./PaymentsHandler.sol";
import "./AccessControl.sol";

/**
    @title Subscription

    @dev Contract for handling subscription based payments with solidity smart contracts.
 */
contract Subscription is AccessControl {
    event Subscribed(address indexed subscriber, uint256 dateSubscribed, uint256 _type);

    struct Subscriber {
        address payerAddress; // The address
        uint256 id; // The id manly for grabbing from array
        uint256 subEnd; // When does the subscription end?
        string secretKey; // The secret key that nobody should know, is CaSe SeNsItIvE
    }

    // Mapping to grab Subscriber based on address
    mapping(address => uint256) private indexOf;

    PaymentsHandler private handler;

    Subscriber[] private subscribers;

    /* Payment types */
    // Note payment costs are mutable

    uint256 private monthlyPay = 0.01 ether; // $5 USD
    uint256 private quarterlyPay = 0.05 ether; // $25 USD
    uint256 private halflyPay = 0.1 ether; // $50 USD
    uint256 private yearlyPay = 0.2 ether; // $100 USD

    // Forgot secret key fee. Note should never change, but for the chance
    // that it causes issues it is mutable
    uint256 private forgotKeyFee = 0.001 ether; // $0.50 USD

    // Array to hold paymenttypes
    uint256[] private paymentTypes = [
        monthlyPay,
        quarterlyPay,
        halflyPay,
        yearlyPay
    ];

    // Array to hold subscription endings
    uint256[] private subscriptionEndings = [
        31 days,
        91 days,
        182 days,
        365 days
    ]; 

    constructor() {
        handler = new PaymentsHandler();
        // Gen Subscriber
        Subscriber memory genSubscriber = Subscriber(
            msg.sender,
            0,
            block.timestamp,
            "Secret Key"
        );
        subscribers.push(genSubscriber);
    }

    modifier onlySubscribed() {
        require(
            indexOf[msg.sender] != 0 || msg.sender == owner(), 
            "Subscriptions: Address is not subscribed."
        );
        _;
    }

    /**
        @dev Subscribe to new payment.

        @param _type uint, the type of subscription.
        @param key string memory, a secret key so only you have access to the subscription.
     */
    function subscribe(uint _type, string memory key) public payable {
        _subscribe(_type, msg.sender, key);
    }

    /**
        @dev Gift or Reward a subscription for someone else.

        @param _type uint, the type of subscription.
        @param subscriber address, the address of the one being gifter or rewarded the subscription.
        @param key string memory, a secret key you decide. Make sure you give the subscriber the key so they can access their subscriptions.
     */
    function giftSubscription(uint _type, address subscriber, string memory key) public payable {
        require(msg.sender != subscriber, "Subscriptions: You can not gift yourself.");
        _subscribe(_type, subscriber, key);
    }

    /**
        @dev Subscribe to new payment.

        @param _type uint the type of payment.
        @param _subscriber address the address of the subscriber
        @param key string memory, a secret key so only you have access to the subscription.

        @return bool success
     */
    function _subscribe(uint _type, address _subscriber, string memory key) private returns (bool) {
        require(_subscriber != address(0), "Subscriptions: You can not subscribe the 0 address.");
        // Grab payment amount
        uint paymentAmount = paymentTypes[_type];
        // Check fee is correct
        require(msg.value == paymentAmount, "Subscriptions: You must pay the EXACT amount.");
        // Pay and check status
        bool status = pay();
        if (!status) {
            return false;
        }

        // Grab when the subscription ends
        uint256 end = subscriptionEndings[_type];

        // Check if already subscribed
        if (indexOf[_subscriber] != 0 || _subscriber == owner()) {
            // Actualiza el subsriber
            Subscriber storage sub = subscribers[indexOf[_subscriber]];
            // Update subscription end and secret key
            sub.secretKey = key;
            // Check if current subscription has ended
            if (block.timestamp > sub.subEnd) {
                // Sub end is the timestamp plus days till over.
                sub.subEnd = block.timestamp + end;
            } else {
                // Add days till over
                sub.subEnd += end;
            }

            // End function here
            return true;
        }
            
        // Update data
        Subscriber memory subscriber = Subscriber(
            _subscriber,
            subscribers.length,
            block.timestamp + end,
            key
        );
        subscribers.push(subscriber);
        indexOf[_subscriber] = subscribers.length - 1;

        emit Subscribed(
            _subscriber,
            block.timestamp,
            _type
        );

        return true;
    }

    /**
        @dev Pay fee

        @return bool success
     */
    function pay() private returns (bool) {
        address payable payAdd = payable(address(handler));
        (bool success, ) = payAdd.call{value:msg.value}("");
        return success;
    }

    /**
        @dev Check if a address is currently subscribed.

        @param _subscriber address, the address in question.

        @return bool subscribed
     */
    function subscribed(address _subscriber) external view onlySubscribed returns (bool) {
        require(_subscriber != address(0), "Subscriptions: Subscriber can not be 0 address.");
        // Grab Subscriber
        Subscriber storage subscriber = subscribers[indexOf[_subscriber]];
        // Return if the subEnd is greater than the timestamp of the current block.
        // If it is greater than the Subscriber is subscribed.
        // Otherwise the Subscriber is not subscribed.
        return subscriber.subEnd > block.timestamp;
    }

    /**
        @dev Verify subscriber.

        @param subscriber address, the address of the subscriber.
        @param secretKey string memory, the secret key for the subscrber.

        @return bool, valid
     */
    function validSubscriber(address subscriber, string memory secretKey) public view returns (bool) {
        require(subscriber != address(0), "Subscriptions: Subscriber can not be 0 address.");

        // Grab subscriber
        Subscriber storage sub = subscribers[indexOf[subscriber]];
        // Check keys
        if (keccak256(abi.encode(secretKey)) == keccak256(abi.encode(sub.secretKey))) {
            // They are the same! Lessgo
            return true;
        } else {
            // Nope somebody is trying to cheat
            return false;
        }
    }

    /**
        @dev YOUR (msg.sender) secret key lookup

        Note returns MSG.SENDER's secret key.
        Note you must pay in order to get your secret key if you forgot it.
     */
    function forgotSecretKey() public payable onlySubscribed returns (string memory) {
        require(msg.value == forgotKeyFee, "Subscriptions: Must send EXACT value.");
        Subscriber storage subscriber = subscribers[indexOf[msg.sender]];
        return subscriber.secretKey;
    }

    /**
        @dev Change YOUR (msg.sender) secret key.

        @param key string memory, The current secret key.
        @param newKey string memory, The new key to change to.
     */
    function changeSecretKey(string memory key, string memory newKey) public onlySubscribed {
        Subscriber storage subscriber = subscribers[indexOf[msg.sender]];
        // Checking keys are the same
        require(
            keccak256(abi.encode(key)) == keccak256(abi.encode(subscriber.secretKey)), 
            "Subscriptions: Keys are not the same."
        );
        // Change key
        subscriber.secretKey = newKey;
    }

    /**
        @dev Get the PaymentHandlers address.

        @return address
     */
    function getHandlerAddress() external view returns (address) {
        return address(handler);
    }

    /**
        @dev Get data for the payment type

        @param _type uint, payment type

        @return (uint price, uint time)
     */
    function getPaymentType(uint _type) external view returns (uint, uint) {
        uint price = paymentTypes[_type];
        uint time = subscriptionEndings[_type];
    
        return (price, time);
    }

    /**
        @dev Getter for forgotKeyFee
     */
    function getForgotKeyFee() external view returns (uint) {
        return forgotKeyFee;
    } 
    
    /**
        @dev Set the handlers address.

        @param handlerAddress the address of the handler.
     */
    function setHandlersAddress(address handlerAddress) external adminOrOwner {
        handler = PaymentsHandler(payable(handlerAddress));
    }

    /**
        @dev Set a Payments price

        @param _type uint, the type of payment (index in array)
        @param payment uint, the price.
     */
    function setPaymentType(uint _type, uint payment) external adminOrOwner {
        require(paymentTypes[_type] == payment, "Subscriptions: Payment is already set to this value.");
        paymentTypes[_type] = payment;
    } 
}