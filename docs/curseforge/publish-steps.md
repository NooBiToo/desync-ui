# Как выложить DeSync UI на CurseForge

Делается один раз со своей учётной записи CurseForge. Дальше для новой версии нужен только шаг «Загрузить файл».

## 1. Собрать архив

В папке проекта:

```
.venv\Scripts\python tools\export_profile.py --sv "<путь к WTF\Account\<аккаунт>\SavedVariables\ElvUI.lua>" --key "<имя профиля ElvUI>" --version <N> --out ElvUI_DeSyncUI\Profile.lua
.venv\Scripts\python tools\build_release.py
```

- Первая команда нужна, только если вы поменяли вид ElvUI и хотите выложить новый. Тогда увеличьте `--version` на 1: у всех, кто поставил сборку, окно предложит «Обновить вид».
- Перед выпуском поднимите `## Version` в `ElvUI_DeSyncUI\ElvUI_DeSyncUI.toc` (например, `1.0.1`).
- Готовый файл: `dist\ElvUI_DeSyncUI-<версия>.zip`.

## 2. Создать проект (один раз)

1. Зайдите на [authors.curseforge.com](https://authors.curseforge.com) → **Create Project** → игра **World of Warcraft**.
2. Название: **DeSync UI**. Краткое описание: «Сборка интерфейса на ElvUI с WindTools и mMediaTag и полезными модулями».
3. Категории: **User Interface**, **Unit Frames**, **Bags & Inventory**.
4. Описание: вставьте текст из `docs\curseforge\description.md`.
5. Лицензия: на ваш выбор (обычно **All Rights Reserved** или **MIT**).
6. Иконка проекта: любая квадратная картинка 400×400 (скриншот интерфейса или логотип).
7. Отправьте проект на модерацию. CurseForge проверяет новые проекты вручную, обычно в течение суток.

## 3. Обязательные зависимости (вкладка Relations)

Добавьте два проекта с типом **Required Dependency**:

- **ElvUI WindTools** (проект 300361)
- **ElvUI mMediaTag & Tools** (проект 289502)

Тогда приложение CurseForge будет ставить их вместе со сборкой. ElvUI сюда добавить нельзя: его нет на CurseForge, поэтому в описании он стоит первой строкой.

## 4. Загрузить файл

1. **Files** → **Upload File** → выберите `dist\ElvUI_DeSyncUI-<версия>.zip`.
2. Display name: `DeSync UI <версия>`.
3. Game Version: отметьте версию **WoW Forever** (16001), если CurseForge предложит её отдельно.
4. Release Type: **Release**.
5. Changelog: что изменилось.

## 5. После создания проекта

Пришлите мне номер проекта (Project ID на странице проекта). Я впишу его в `.toc` строкой `## X-Curse-Project-ID: <номер>`: по ней приложения обновления узнают сборку.
