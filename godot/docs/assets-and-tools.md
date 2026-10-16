# Character presentation, authoring и исследовательские инструменты

Статус: **IMPLEMENTED** для canonical MMO pipeline; rig/reference ветви —
**EXPERIMENTAL/HISTORICAL**. [Карта клиента](../../ARCHITECTURE.md).

## Runtime package

Сервер сообщает semantic character_model_id и bounded appearance. Клиентская
mapping проверяет совместимость catalog, выбирает локальный пакет и применяет
визуальные варианты для Creator, owner и remote одинаково. Неподдерживаемая
модель/пакет отвергается, а не подменяется default character. Collider строится
по server-selected body profile, а не alpha bounds PNG.

Пакет содержит отдельные RGBA frames 256×256 и native SpriteFrames.tres с order,
FPS и loop. Frame contract связывает physical_height_cm с 1 px/cm и root pivot
(128,236); общий parent display transform одинаков для моделей/animations.
AnimationLibrary проверяет обязательные directional idle/walk и пути текстур.
Runtime выбирает prepared стороны без mirroring locomotion. Gait использует
rendered distance и stop debounce; correction transforms не становятся шагами.

Contact response может выбрать receiver-relative stumble; такой optional reaction
не меняет физику. Подготовленный back reaction допускает presentation mirror,
отдельный front reaction зависит от наличия art. Ordered damage_resolved создаёт
native scene с Label/AnimationPlayer, которая удаляется после завершения animation.
Это отображение damage event, не реализация HP. Visual Stall временно выбирает
короткий loop текущей SpriteFrames animation и восстанавливает исходный ресурс.

## Offline raster pipeline

Source sheets и reference art находятся вне res://assets, в references. Агент
или художник выбирает pose, root/body measurements и cleanup plan. frame_tools
выполняет отдельные детерминированные extract/clean/resize/mirror/prepare/inspect/
heuristic/place/render operations; он не знает model IDs или MMO pivot.
Heuristic даёт диагностическое предположение, которое нельзя автоматически
считать reviewed placement. Альфа bbox не определяет рост персонажа.

character_assets связывает универсальные primitives с MMO package:
проверяет окружение и frames, собирает SpriteFrames через native Godot builder
и воспроизводит committed recipes. Replay проверяет tracked inputs и source
SHA256, пишет только temporary outputs и сравнивает canonical bytes. Он не
угадывает рецепт и не исправляет source. Render-review создаёт изображение для
визуальной проверки, не runtime authority. Ошибки source/hash/geometry останавливают
операцию. [Точные операции](../tools/character_asset_llm_analysis.md),
[рецепты](../tools/character_recipes/locomotion_v1/README.md),
[server presentation contract](../../../ai_research/v3/game/docs/character-sprite-frame-contract.md).

## Эксперименты и проверочные consumers

Mannequin/rig scripts строят mesh/Polygon2D/Bone2D binding experiments, рендерят
pose previews и валидируют geometry/weights/assets. Их scenes и generated previews
не являются canonical MMO locomotion. Архив rc3_rigid_cutout сохраняет отвергнутый
подход. reference_projects содержат отдельный Skeleton2D demo project с адаптациями
Kotone и human skeleton reference; свои project/scenes/licenses остаются локальными
для этих experiments. Загрузка MMO Login не запускает их.

Tests — отдельные scripts/scenes для pure contracts, native frames, UI и реальных
peers. Они читают fixtures и сообщают assertions; это не product controller.
Source `.uid`/`.import` sidecars versioned, `.godot` caches generated. Локальные
изменения рецептов/настроек и untracked art требуют отдельного validation; факт
наличия файла не делает новый animation package принятым.
