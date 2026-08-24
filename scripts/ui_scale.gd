extends RefCounted
class_name UiScale
## Single definition of how the HUD scales with the window.
##
## Every panel and plate is authored at REFERENCE_HEIGHT and multiplied by `of(viewport)`, so
## the interface keeps its proportions on a laptop instead of shrinking to a postage stamp on
## a large display. It lives here rather than in each panel so the party portraits, the
## inventory and anything added later cannot drift to different rules.
##
## Height rather than width, because these layouts stack vertically and a wide-but-short
## window should not inflate them.
##
## Raise REFERENCE_HEIGHT to make everything smaller, lower it to make everything bigger.

const REFERENCE_HEIGHT := 1080.0
## Held to this range so neither a tiny window nor a huge one produces something silly.
const MIN_SCALE := 0.9
const MAX_SCALE := 1.8


static func of(viewport: Viewport) -> float:
	if viewport == null:
		return 1.0
	return clampf(viewport.get_visible_rect().size.y / REFERENCE_HEIGHT, MIN_SCALE, MAX_SCALE)
