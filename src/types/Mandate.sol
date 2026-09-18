// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// Whether a charge can be reversed. Prepaid charges buy service that has not
/// been delivered yet, so a reversal is really a late cancellation and the
/// merchant caps its loss by cutting off service. Postpaid charges bill for
/// consumption that already happened and are never reversible.
enum ChargeKind {
    Prepaid,
    Postpaid
}

/// A payer's standing authorisation for one merchant to pull one token.
/// `maxAmount` caps a single charge, `minInterval` is the floor on the gap
/// between them, and `maxCharges` of zero means open ended.
struct Mandate {
    address payer;
    address merchant;
    address token;
    uint256 maxAmount;
    uint64 minInterval;
    uint64 startsAt;
    uint64 expiresAt;
    uint32 maxCharges;
    ChargeKind chargeKind;
    bytes32 salt;
}

library MandateLib {
    bytes32 internal constant MANDATE_TYPEHASH = keccak256(
        "Mandate(address payer,address merchant,address token,uint256 maxAmount,uint64 minInterval,uint64 startsAt,uint64 expiresAt,uint32 maxCharges,uint8 chargeKind,bytes32 salt)"
    );

    /// EIP-712 struct hash. Also serves as the mandate id, which is why `salt`
    /// exists: without it two otherwise identical mandates would collide.
    function hash(Mandate memory m) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                MANDATE_TYPEHASH,
                m.payer,
                m.merchant,
                m.token,
                m.maxAmount,
                m.minInterval,
                m.startsAt,
                m.expiresAt,
                m.maxCharges,
                uint8(m.chargeKind),
                m.salt
            )
        );
    }
}
