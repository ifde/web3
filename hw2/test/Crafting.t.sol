// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {
    IERC1155Receiver
} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {CraftingV1} from "../src/CraftingV1.sol";
import {CraftingV2} from "../src/CraftingV2.sol";

// Тестовый контракт: получатель ERC-1155 токентов
// Нужен, чтобы проверить отправку токенов не обычному пользователю,
// а контракту, который может принять или отклонить токены.
contract CraftingReceiver is IERC1155Receiver {
    bool public reject;

    // Включает или выключает отказ контракта от получения токенов.
    function setReject(bool value) external {
        reject = value;
    }

    // Запускает крафт от имени самого receiver.
    function craft(CraftingV1 token) external {
        token.craft(1);
    }

    // ERC-1155 вызывает эту функцию после отправки токенов контракту.
    // operator — кто начал перевод, from — откуда отправили токены.
    // id — тип токена, value — количество, data — дополнительные данные.
    // Возвращаем selector, чтобы подтвердить безопасный приём токенов.
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        require(!reject, "receiver rejected");
        return IERC1155Receiver.onERC1155Received.selector;
    }

    // То же самое подтверждение для пакетной отправки нескольких токенов.
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external view returns (bytes4) {
        require(!reject, "receiver rejected");
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    // Сообщает ERC-165, что контракт поддерживает интерфейс ERC-1155 receiver.
    // interfaceId — это короткий идентификатор интерфейса контракта размером bytes4
    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

contract CraftingTest is Test {
    bytes32 internal constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    CraftingV1 internal v1;
    CraftingV2 internal v2;
    CraftingReceiver internal receiver;

    address internal gameOwner = makeAddr("gameOwner");
    address internal proxyAdminOwner = makeAddr("proxyAdminOwner"); // отдельный контракт, владелец которого имеет право менять implementation в Transparent Proxy
    address internal player = makeAddr("player");
    address internal operator = makeAddr("operator");
    address internal newHolder = makeAddr("newHolder");

    // Разворачивает V1 через Transparent Proxy и создаёт тестовый receiver.
    // Прокси — это контракт-посредник, который хранит состояние и перенаправляет вызовы в другой контракт
    // User ----- Proxy  ---- delegatecall ---->  CraftingV1
    function setUp() public {
        address proxy = Upgrades.deployTransparentProxy(
            // разворачиваем CraftingV1 через прокси
            "CraftingV1.sol:CraftingV1",
            proxyAdminOwner,
            abi.encodeCall(CraftingV1.initialize, (gameOwner)) // при деплое кодирует вызов функции initialize вместе с аргументом gameOwner
        );

        v1 = CraftingV1(proxy);
        receiver = new CraftingReceiver();
    }

    // Проверяет обычное создание одного меча из ресурсов.
    function testCraft() public {
        _issueResources(player, 3, 2);

        vm.prank(player);
        v1.craft(1);

        assertEq(v1.balanceOf(player, v1.WOOD()), 0);
        assertEq(v1.balanceOf(player, v1.ORE()), 0);
        assertEq(v1.balanceOf(player, v1.SWORD()), 1);
        assertEq(v1.totalCrafted(), 1);
    }

    // Проверяет права issue и запрет нулевого количества и мечей.
    function testIssueRules() public {
        vm.startPrank(gameOwner);
        (bool success,) = address(v1).call(abi.encodeCall(CraftingV1.issue, (player, v1.SWORD(), 1)));
        vm.stopPrank();
        assertFalse(success);

        vm.startPrank(player);
        (success,) = address(v1).call(abi.encodeCall(CraftingV1.issue, (player, v1.WOOD(), 1)));
        vm.stopPrank();
        assertFalse(success);

        vm.startPrank(gameOwner);
        (success,) = address(v1).call(abi.encodeCall(CraftingV1.issue, (player, v1.WOOD(), 0)));
        vm.stopPrank();
        assertFalse(success);
    }

    // Нельзя создать нулевое количество мечей.
    function testCraftZeroReverts() public {
        vm.startPrank(player);
        vm.expectRevert();
        v1.craft(0);
        vm.stopPrank();
    }

    // Крафт отклоняется, если не хватает дерева.
    function testCraftRevertsForMissingWood() public {
        _issueResources(player, 2, 2);

        vm.startPrank(player);
        vm.expectRevert();
        v1.craft(1);
        vm.stopPrank();
    }

    // Крафт отклоняется, если не хватает руды.
    function testCraftRevertsForMissingOre() public {
        _issueResources(player, 3, 1);

        vm.startPrank(player);
        vm.expectRevert();
        v1.craft(1);
        vm.stopPrank();
    }

    // Проверяет upgrade, сохранение данных и разбор меча новым держателем.
    function testOnlyOwnerCanUpgradeAndStateIsPreserved() public {
        _issueResources(player, 3, 2);
        vm.prank(player); // вызов prank действует только на 1 строчку ниже
        v1.craft(1);

        vm.prank(player); // снова вызываем prank
        v1.setApprovalForAll(operator, true); // operator — это адрес, которому владелец токенов (игрок 1) разрешает управлять всеми своими ERC‑1155 токенами

        Upgrades.upgradeProxy(
            address(v1),
            "CraftingV2.sol:CraftingV2",
            "",
            proxyAdminOwner
        );

        v2 = CraftingV2(address(v1));
        assertEq(v2.owner(), gameOwner);
        assertEq(v2.balanceOf(player, v2.SWORD()), 1);
        assertTrue(v2.isApprovedForAll(player, operator));
        assertEq(v2.totalCrafted(), 1);
        assertEq(v2.totalSalvaged(), 0);

        vm.startPrank(operator);
        v2.safeTransferFrom(player, newHolder, v2.SWORD(), 1, "");
        vm.stopPrank();

        vm.prank(newHolder);
        v2.salvage(1);
        assertEq(v2.balanceOf(newHolder, v2.SWORD()), 0);
        assertEq(v2.balanceOf(newHolder, v2.ORE()), 1);
        assertEq(v2.totalSalvaged(), 1);
    }

    // Повторная инициализация прокси и implementation должна завершиться revert.
    function testInitializersCannotBeCalledTwice() public {
        vm.expectRevert();
        v1.initialize(player); // попытка вызвать функцию инициализации контракта и установить player владельцем игры

        // user -> CraftingV1
        // когда у нас был деплой через прокси: user -> Proxy -> CraftingV1
        CraftingV1 implementation = new CraftingV1();
        vm.expectRevert();
        implementation.initialize(player); // после вызова конструктора initialize() должен быть заблокирован
    }

    // Владелец игры не может обновить прокси вместо владельца ProxyAdmin.
    function testDifferentAddressesOwnGameAndProxyAdmin() public {
        assertTrue(gameOwner != proxyAdminOwner);
        assertEq(v1.owner(), gameOwner);

        address proxyAdmin = address(uint160(uint256(vm.load(address(v1), ADMIN_SLOT))));
        CraftingV2 implementation = new CraftingV2();

        vm.startPrank(gameOwner);
        vm.expectRevert();
        // пытаемся сделать апгрейд от имени gameOwner 
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(v1)), // текущий адре прокси (остается тем же )
            address(implementation), // передает новый вариант реализации CraftingV2 
            "" // не вызываем никакой фукнции 
        );
        vm.stopPrank();
    }

    // Отказ receiver откатывает сжигание ресурсов, выпуск меча и счётчик.
    function testReceiverRejectsCraftAndStateIsRolledBack() public {
        vm.startPrank(gameOwner);
        v1.issue(address(receiver), v1.WOOD(), 3);
        v1.issue(address(receiver), v1.ORE(), 2);
        vm.stopPrank();

        receiver.setReject(true);
        vm.expectRevert("receiver rejected");
        receiver.craft(v1);

        assertEq(v1.balanceOf(address(receiver), v1.WOOD()), 3);
        assertEq(v1.balanceOf(address(receiver), v1.ORE()), 2);
        assertEq(v1.balanceOf(address(receiver), v1.SWORD()), 0);
        assertEq(v1.totalCrafted(), 0);
    }

    // Нельзя разобрать меч, которого нет на балансе.
    function testSalvageWithoutSwordReverts() public {
        Upgrades.upgradeProxy(
            address(v1),
            "CraftingV2.sol:CraftingV2",
            "",
            proxyAdminOwner
        );
        v2 = CraftingV2(address(v1));

        vm.startPrank(player);
        vm.expectRevert();
        v2.salvage(1);
        vm.stopPrank();
    }

    // Проверяет, что после крафта и разбора остаётся только нужное количество руды.
    function testFuzzCraftAndSalvage(uint256 amount) public {
        amount = bound(amount, 1, 1000);
        _issueResources(player, amount * 3, amount * 2);

        Upgrades.upgradeProxy(
            address(v1),
            "CraftingV2.sol:CraftingV2",
            "",
            proxyAdminOwner
        );
        v2 = CraftingV2(address(v1));

        vm.prank(player);
        v2.craft(amount);
        vm.prank(player);
        v2.salvage(amount);

        assertEq(v2.balanceOf(player, v2.WOOD()), 0);
        assertEq(v2.balanceOf(player, v2.ORE()), amount);
        assertEq(v2.balanceOf(player, v2.SWORD()), 0);
        assertEq(v2.totalCrafted(), amount);
        assertEq(v2.totalSalvaged(), amount);
    }

    // Выдаёт игроку дерево и руду от имени владельца игры.
    function _issueResources(address to, uint256 wood, uint256 ore) internal {
        vm.startPrank(gameOwner); // временно делает gameOwner отправителем следующих вызовов
        v1.issue(to, v1.WOOD(), wood);
        v1.issue(to, v1.ORE(), ore);
        vm.stopPrank();
    }
}
