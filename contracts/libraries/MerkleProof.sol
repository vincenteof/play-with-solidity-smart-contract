// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library MerkleProof {
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) public pure returns (bool) {
        bytes32 hash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            hash = index % 2 == 0
                ? keccak256(abi.encodePacked(hash, proofElement))
                : keccak256(abi.encodePacked(proofElement, hash));
            index /= 2;
        }
        return hash == root;
    }

    function verifyBySorting(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) public pure returns (bool) {
        bytes32 hash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            hash = hash < proofElement
                ? keccak256(abi.encodePacked(hash, proofElement))
                : keccak256(abi.encodePacked(proofElement, hash));
        }
        return hash == root;
    }
}
