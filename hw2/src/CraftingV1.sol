// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ERC1155Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {
    ERC1155BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";

/**
 * @dev ERC-1155 может выпускать разные типы токенов в одном контракте. В нашем случае:
 *
 * tokenId = 1 — дерево
 * tokenId = 2 — руда
 * tokenId = 3 — меч
 *
 */
contract CraftingV1 is
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155BurnableUpgradeable
{
    uint256 public constant WOOD = 1;
    uint256 public constant ORE = 2;
    uint256 public constant SWORD = 3;

    uint256 public totalCrafted; // сколько мечей создано

    event Crafted(address indexed player, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// модификатор initializer гарантирует, что функцию нельзя вызвать повторно
    function initialize(address owner) public initializer {
        __ERC1155_init("");
        __Ownable_init(owner);
        __ERC1155Burnable_init();
    }

    /// @dev Владелец может выдавать только дерево и руду.
    function issue(address to, uint256 id, uint256 amount) external onlyOwner {
        require(to != address(0), "zero recipient");
        require(amount > 0, "zero amount");
        require(id == WOOD || id == ORE, "invalid resource");

        // mint — создать новые токены и добавить их на баланс
        _mint(to, id, amount, "");
    }

    /// @dev Для одного меча нужно 3 дерева и 2 руды. Virtual тут на всякий случай, мы его все равно не переопределяем в V2
    function craft(uint256 amount) external virtual {
        require(amount > 0, "zero amount");

        // burn — уничтожить токены и убрать их с баланса
        // здорово, что _burn под капотом уже проверяет, что у пользователя досаточно баланса
        // balanceOf(msg.sender, id) >= amount
        _burn(msg.sender, WOOD, amount * 3);
        _burn(msg.sender, ORE, amount * 2);
        totalCrafted += amount;
        _mint(msg.sender, SWORD, amount, "");

        emit Crafted(msg.sender, amount);
    }
}
