class_name WorldConfig
extends RefCounted
## Constantes do mundo lógico. Fonte única de verdade para coordenadas.
## Valores portados de MortivaneV97.html (W, H, MARGIN, BATTLEFIELD, DEPLOY_X, PORTAL).

## Mundo lógico: 1000 × 560, como no HTML. Toda a lógica usa esta unidade.
const WIDTH := 1000.0
const HEIGHT := 560.0
const SIZE := Vector2(WIDTH, HEIGHT)
const CENTER := Vector2(WIDTH / 2.0, HEIGHT / 2.0)

## Margem das bordas do campo (HTML: MARGIN = 26).
const MARGIN := 26.0

## Linha do chão: acima dela é céu da arte (HTML: BATTLEFIELD.topY = round(560 * 0.375)).
const BATTLEFIELD_TOP_Y := 210.0

## Área jogável: x 26..974, y 210..534.
const BATTLEFIELD_RECT := Rect2(MARGIN, BATTLEFIELD_TOP_Y, WIDTH - 2.0 * MARGIN, HEIGHT - MARGIN - BATTLEFIELD_TOP_Y)

## Divisa entre os lados: jogador à esquerda (HTML: DEPLOY_X = W * 0.5).
const DEPLOY_X := 500.0

## Portal (HTML: PORTAL_GROUND_BREAK_Y = round(560 * 0.49) + DEMON_EMERGE_OFFSET_Y;
## PORTAL = { x: W/2, y: round(PORTAL_GROUND_BREAK_Y - 46 * 1.8), r: 46 }).
const DEMON_EMERGE_OFFSET_Y := -15.0
const PORTAL_GROUND_BREAK_Y := 259.0
const PORTAL_RADIUS := 46.0
const PORTAL_POSITION := Vector2(500.0, 176.0)

## Enquadramento (HTML V65/V67): em telas mais largas que 1000:490, o palco pode
## esconder até 70 unidades de altura — 80% do corte sai do céu, 20% do rodapé.
## O gameplay nunca é distorcido.
const MIN_VISIBLE_HEIGHT := 490.0
const TOP_CROP_SHARE := 0.8

## A arte de fundo é ancorada ao mundo nesta altura (HTML V68: y ≈ 380).
const ART_ANCHOR_Y := 380.0
