// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title InvoiceRail — one end-to-end stablecoin payment flow
/// @notice A merchant issues an invoice in an ERC-20 stablecoin; a payer can settle it in parts;
///         the contract holds the funds until the merchant withdraws, and emits an event on every
///         state change so a bookkeeper can reconcile without indexing raw transfers.
/// @dev No owner, no upgradeability, no fees. The token is fixed at deploy time. Transfers are
///      verified by balance delta, so fee-on-transfer tokens cannot make the books lie.
contract InvoiceRail {
    struct Invoice {
        address merchant;
        uint128 amount;      // total due
        uint128 paid;        // collected and not yet withdrawn
        uint64  dueAt;       // unix seconds; payments rejected after this
        bool    settled;     // paid in full at least once
        bool    cancelled;   // merchant cancelled after the due date
    }

    IERC20 public immutable token;
    mapping(bytes32 => Invoice) public invoices;

    event InvoiceCreated(bytes32 indexed id, address indexed merchant, uint256 amount, uint64 dueAt);
    event InvoicePaid(bytes32 indexed id, address indexed payer, uint256 amount, uint256 paidTotal);
    event InvoiceSettled(bytes32 indexed id, address indexed merchant, uint256 amount);
    event InvoiceWithdrawn(bytes32 indexed id, address indexed merchant, uint256 amount);
    event InvoiceCancelled(bytes32 indexed id, address indexed merchant);

    error ZeroAmount();
    error DueInPast();
    error InvoiceExists();
    error UnknownInvoice();
    error AlreadySettled();
    error Cancelled();
    error PastDue();
    error NotMerchant();
    error NotPastDue();
    error Overpayment(uint256 remaining);
    error TransferFailed();

    constructor(IERC20 _token) {
        token = _token;
    }

    function createInvoice(bytes32 id, uint128 amount, uint64 dueAt) external returns (bytes32) {
        if (amount == 0) revert ZeroAmount();
        if (dueAt <= block.timestamp) revert DueInPast();
        if (invoices[id].merchant != address(0)) revert InvoiceExists();
        invoices[id] = Invoice(msg.sender, amount, 0, dueAt, false, false);
        emit InvoiceCreated(id, msg.sender, amount, dueAt);
        return id;
    }

    /// @notice Pay an invoice, in full or in part. Overpayment is rejected rather than refunded so
    ///         the payer's wallet shows exactly what happened.
    function pay(bytes32 id, uint128 amount) external {
        Invoice storage inv = invoices[id];
        if (inv.merchant == address(0)) revert UnknownInvoice();
        if (inv.cancelled) revert Cancelled();
        if (block.timestamp > inv.dueAt) revert PastDue();
        if (amount == 0) revert ZeroAmount();
        if (inv.settled) revert AlreadySettled();

        uint256 remainingAmount = uint256(inv.amount) - uint256(inv.paid);
        if (amount > remainingAmount) revert Overpayment(remainingAmount);

        uint256 before = token.balanceOf(address(this));
        _safeTransferFrom(msg.sender, address(this), amount);
        if (token.balanceOf(address(this)) - before != amount) revert TransferFailed();

        inv.paid = uint128(uint256(inv.paid) + amount);
        emit InvoicePaid(id, msg.sender, amount, inv.paid);
        if (inv.paid == inv.amount) {
            inv.settled = true;
            emit InvoiceSettled(id, inv.merchant, inv.amount);
        }
    }

    /// @notice The merchant takes the collected funds, including partial payments.
    function withdraw(bytes32 id) external {
        Invoice storage inv = invoices[id];
        if (inv.merchant == address(0)) revert UnknownInvoice();
        if (msg.sender != inv.merchant) revert NotMerchant();
        if (inv.cancelled) revert Cancelled();
        uint256 available = inv.paid;
        if (available == 0) revert ZeroAmount();

        inv.paid = 0;
        emit InvoiceWithdrawn(id, msg.sender, available);
        _safeTransfer(msg.sender, available);
    }

    /// @notice After the due date the merchant can cancel an unpaid or partly paid invoice; the
    ///         contract stops accepting payments. Collected funds stay withdrawable.
    function cancel(bytes32 id) external {
        Invoice storage inv = invoices[id];
        if (inv.merchant == address(0)) revert UnknownInvoice();
        if (msg.sender != inv.merchant) revert NotMerchant();
        if (block.timestamp <= inv.dueAt) revert NotPastDue();
        inv.cancelled = true;
        emit InvoiceCancelled(id, msg.sender);
    }

    /// @notice Remaining amount due, for a UI or a script.
    function remaining(bytes32 id) external view returns (uint256) {
        Invoice storage inv = invoices[id];
        if (inv.merchant == address(0)) revert UnknownInvoice();
        return uint256(inv.amount) - uint256(inv.paid);
    }

    function _safeTransferFrom(address from, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = address(token).call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }

    function _safeTransfer(address to, uint256 amount) private {
        (bool ok, bytes memory ret) =
            address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }
}
