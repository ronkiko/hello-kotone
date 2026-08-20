# Kotone v2

Это набор спрайтов новой формы Котоне после henshin.

## Ready For Use

Файлы `running_*.png` подготовлены для текущего canvas-рендера:

- `running_front.png`
- `running_back.png`
- `running_left.png`
- `running_right.png`

Каждый файл имеет формат PNG RGBA, размер `780x130` и шесть кадров по
`130x130`. Фон прозрачен, подписи удалены, кадры выровнены по единому размеру.

## Reference

`reference/renew-all-states.png` сохраняет исходный лист ChatGPT со всеми
показанными состояниями: dash, skid, jump, landing, hurt и victory.

Эти дополнительные состояния пока не вынесены в отдельные production-ready
PNG: в исходном листе они перекрываются, имеют разный размер и содержат
встроенные эффекты. Не использовать их напрямую как sprite sheet.

## Source

Исходный reference-пакет находится в `kotone-sprites-reference/renew/` и может
быть удалён после проверки этого набора. Игровой код этим набором пока не
изменялся.
