// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./libraries/MerkleProof.sol";

contract MerkleProofVerifier {
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) public pure returns (bool) {
        return MerkleProof.verify(proof, root, leaf, index);
    }

    function verifyBySorting(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) public pure returns (bool) {
        return MerkleProof.verifyBySorting(proof, root, leaf);
    }
}
