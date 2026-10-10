// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CraftingV1} from "./CraftingV1.sol";

/// @custom:oz-upgrades-from CraftingV1
contract CraftingV2 is CraftingV1 {
    uint256 public totalSalvaged; // это общий счётчик всех разобранных мечей

    event Salvaged(address indexed player, uint256 amount);

    /// @dev Меч разбирается обратно в одну единицу руды.
    function salvage(uint256 amount) external {
        require(amount > 0, "zero amount");

        _burn(msg.sender, SWORD, amount);
        totalSalvaged += amount;
        _mint(msg.sender, ORE, amount, "");

        emit Salvaged(msg.sender, amount);
    }
}
