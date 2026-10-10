# Фролов Иван Григорьевич, БПИ-235№
### Домашнее задание №2 

## Правила

- дерево — `id = 1`;
- руда — `id = 2`;
- меч — `id = 3`;
- `issue` выдаёт дерево и руду, вызвать её может только владелец игры;
- `craft(n)` сжигает `3 * n` дерева и `2 * n` руды и создаёт `n` мечей;
- `salvage(n)` в V2 сжигает `n` мечей и выдаёт `n` руды.

Мечи нельзя создать через `issue`. Если контракт-получатель отклоняет токены,
вся операция откатывается.

## Структура

- `src/CraftingV1.sol` — первая версия контракта;
- `src/CraftingV2.sol` — версия с `salvage`;
- `test/Crafting.t.sol` — тесты, upgrade и fuzz-тест;
- `foundry.toml` — настройки Foundry.

## Версии

- Solidity — `0.8.27`;
- Foundry — `1.5.1`;
- `forge-std` — `1.17.0`;
- OpenZeppelin Contracts Upgradeable — `5.7.0`;
- OpenZeppelin Foundry Upgrades — `0.4.2`.

## Установка

```bash
forge install --no-git foundry-rs/forge-std@v1.17.0
forge install --no-git OpenZeppelin/openzeppelin-contracts-upgradeable@v5.7.0
forge install --no-git OpenZeppelin/openzeppelin-foundry-upgrades@v0.4.2
```

## Обновление

Используется Transparent Proxy. Пользователь всегда обращается к адресу
прокси, а не напрямую к implementation. При обновлении меняется только адрес
implementation, поэтому сохраняются адрес прокси, владелец игры, балансы,
разрешения операторов и `totalCrafted`.

В V2 новая переменная `totalSalvaged` добавляется после данных V1. 

## Запуск

```bash
forge build # компилируем
FOUNDRY_FUZZ_RUNS=20 forge test --match-path test/Crafting.t.sol --force -vvvv # тесты (ограничиваем число Fuzzy запусков, иначе очень долго работает) 
forge test --rerun --force # (перезапустить только упавшие тесты)
```

## Результат тестов 

```bash 
Suite result: ok. 11 passed; 0 failed; 0 skipped; finished in 33.03s (35.40s CPU time)
```