;; title:   BrightOn!
;; author:  Grant Williams
;; desc:    A puzzle game inspired by LightsOut.
;; site:    grantwilliams.info/brighton
;; license: CC-BY 4.0
;; version: 0.1
;; script:  fennel
;; saveid:  BrightOn 
;; input:   mouse


(macro inc! [x] `(set ,x (+ ,x 1)))

; mutual recursion requires forward 
; declaration
(var to-str nil)
(var t-to-str nil)
(var a-to-str nil)

; my own to-string for debugging.
; fennel has one in a library but it
; doesn't seem to be available.
(set to-str (fn [val]
 (if (= (type val) :nil) :nil
 		  (= (type val) :table)
     	(if (not (. val 1))
      		(t-to-str val)
        (a-to-str val))
   		(tostring val))))

(set t-to-str (fn [tab]
 (local strs [])
 (each [k v (pairs tab)]
 	(table.insert strs (to-str k))
  (table.insert strs (to-str v)))
 (.. "{" 
 	(table.concat strs " ") "}")))
  
(set a-to-str (fn [arr]
	(local strs [])
	(each [_ v (ipairs arr)]
		(table.insert strs (to-str v)))
	(.. "[" 
		(table.concat strs " ") "]")))
		
(lambda clone [val]
	(if (= (type val) :table)
		(do
			(local cloned {})
			(each [k v (pairs val)]
				(tset cloned k (clone v)))
			cloned)
		val))
		
(fn tab-2d [cols rows]
	(local ret [])
	(for [i 1 rows]
		(local row [])
		(for [i 1 cols]
			(table.insert row 0))
		(table.insert ret row))
 ret)
 
(local [scr-width-px scr-height-px]
							[240          136])
(var   [field-w field-h]
							[8       8]) ; start with max
;; top left tile coord of first light
(local [field-x field-y]
							[13        1])
(local [field-bord-x field-bord-y]
       [13           1])

;; last mouse state
(var last-mouse [0 0 0 0 0 0 0])

;; whether the mouse just clicked
;; the [left middle right]
(var mouse-went-down 
	[false false false])

;; pixels per tile
(local [px-per-t-x px-per-t-y] [8 8])

;; top left of field coords
(local [field-x-px field-y-px]
	[(* px-per-t-x field-x)
	 (* px-per-t-y field-y)])						
(local [field-w-px field-h-px]
 [(* field-w px-per-t-x 2)
  (* field-h px-per-t-y 2)])

;; the four frames of brightness
;; each is 2x2
(local lite-sprites [8 10 12 14])

;; how to draw the hovered-over light
(local hover-sprite 10)

;; top left sprite of border 9-square
(local bord-9 32)

;; 16*8 sprite for new game buttons
(local game-btn-sprite 80)

;; offset of sprite index below another
;; sprite index.
(local sprite-below-off 16)

(var showing-hint false)

;; time it takes to go from dark to bright
(local brite-time-ms 250)
(local fully-on brite-time-ms)
(local fully-off 0)

;; time at which we're more bright than not
(local half-brite (/ brite-time-ms 2))
(local trd-brite (/ brite-time-ms 3))
(local ttrd-brite (* 2 trd-brite))

(local ticks-per-sec 60)
(local ms-per-tick 
	(* 1000 (/ 1 ticks_per_sec)))

(local [lite-t-w lite-t-h] [2 2])
(local [lite-px-w lite-px-h]
	[(* 8 lite-t-w) (* 8 lite-t-h)])
	
(local [hintbtn-w hintbtn-h] [24 8])
(local [hintbtn-x hintbtn-y] [0 80])
	
(local [ng-w ng-h] [24 8])
(local [ng3x3-x ng3x3-y] [0 104])
(local [ng4x4-x ng4x4-y] [24 104])
(local [ng5x5-x ng5x5-y] [48 104])
(local [ng6x6-x ng6x6-y] [0 112])
(local [ng7x7-x ng7x7-y] [24 112])
(local [ng8x8-x ng8x8-y] [48 112])
(local [reset-w reset-h] [72 8])
(local [reset-x reset-y] [0 120])

;; the brightness state of the lights:
;; 0 means minimum brightness
;; brite-time-ms means max brightness
(local brite-state 
	(tab-2d field-w field-h))

;; row-major bitvect: 1 = on, 0 = off
(var lite-state 0)

;; solution bitvect: all 1s must be
;; toggled.
(var solution 0)

;; player toggles. needed to compare
;; with solution for hint
(var choices 0)

(var current-seed 0)

(var game-won false)

;; max rng range for board generation
(local seed-min 1)
(local seed-max 999)

;; number of toggles 
;; going to keep constant for now
;; and use board size as a proxy for
;; difficulty. This value should work
;; for all sizes up to 8x8 
(local difficulty 32)
				
(fn brite-lvl [col row]
	"get the brightness level of a light.
	 0 is dimmest, 3 is brightest."
	(local brite-ms (. brite-state row col))
	(math.floor (/ brite-ms trd-brite))) 

(fn point-inside? [x y tlx tly w h]
	"determines if the given xy coords
	are inside the given area. assumes
	range is half-open."
	(and (>= x tlx) (>= y tly)
						(< x (+ tlx w))
						(< y (+ tly h)))
)  

(fn where-pix [x y]
		"returns what the given pixel coords
		are on top of. used by the mouse.
		returns 'nowhere' if not over anything."
	(if (point-inside? x y 
					 field-x-px field-y-px 
						field-w-px field-h-px)
							"field"
					(point-inside? x y
						hintbtn-x hintbtn-y
						hintbtn-w hintbtn-h)
							"hint"
					(point-inside? x y 
					 ng3x3-x ng3x3-y ng-w ng-h)
					 	"ng3x3"
					(point-inside? x y
						ng4x4-x ng4x4-y ng-w ng-h)
							"ng4x4"
					(point-inside? x y
						ng5x5-x ng5x5-y ng-w ng-h)
							"ng5x5"
					(point-inside? x y
						ng6x6-x ng6x6-y ng-w ng-h)
							"ng6x6"
					(point-inside? x y
						ng7x7-x ng7x7-y ng-w ng-h)
						 "ng7x7"
					(point-inside? x y
						ng8x8-x ng8x8-y ng-w ng-h)
							"ng8x8"
					(point-inside? x y
						reset-x reset-y reset-w reset-h)
						 "reset"
					"nowhere")
)

		
(fn where-mouse []
	"returns what the mouse is over or false."
	(local [x y] (table.pack (mouse)))
	(where-pix (mouse))
)

(fn which-lite	[x y]
	"returns the col,row of the light the
	given pixel is over if it's in the 
	field, otherwise nil."
	(if (not= "field" (where-pix x y)) nil
		(let [
			off-x-px (- x field-x-px)
			off-y-px (- y field-y-px)
			lite-col (/ off-x-px lite-px-w)
			lite-row (/ off-y-px lite-px-h)]
			(when (and 
				(< lite-col field-w)
				(< lite-row field-h)) 
				[(+ 1 (math.floor lite-col))
			 	(+ 1 (math.floor lite-row))])))
)
		
(fn mset-offset [offx offy]
	"returns a function which calls mset
	 but with the given offset."
	(fn [col row val]
		(mset 
			(+ offx col) (+ offy row) val)))
	
(fn unpack-9square [spr-idx]
	"given the sprite index of the top
	 left corner, unpacks a 9square into
		its 9 sprite indices. 
		order: tl t tr l c r bl b br"
	[spr-idx (+ 1 spr-idx) (+ 2 spr-idx)
	 (+ sprite-below-off spr-idx)
		(+ 1 sprite-below-off spr-idx)
		(+ 2 sprite-below-off spr-idx)
		(+ (* 2 sprite-below-off) spr-idx)
		(+ 1 (* 2 sprite-below-off) spr-idx)
		(+ 2 (* 2 sprite-below-off) spr-idx)])
				
(fn draw-9square 
	[spr-idx dst-col dst-row w h fill?]
	"draws a 9-square whose top left tile
	 is the given sprite index. w and h are
		the client rectangle. fill? is whether
		to draw the center or only the borders."
	(local [tl t tr l c r bl b br]
		(unpack-9square	spr-idx))
	(local mset 
		(mset-offset dst-col dst-row))
	
	; corners
	(mset 0 0 tl)
	(mset (+ 1 w) 0 tr)
	(mset 0 (+ 1 h) br)
	(mset (+ 1 w) (+ 1 h) bl)
	
	; top and bottom
	(for [col 1 w]
		(mset col 0 t)
		(mset col (+ 1 h) b))
	
	; left and right
	(for [row 1 h]
		(mset 0 row l)
		(mset (+ 1 w) row r))
	
	; center if applicable
	; todo
)			
				
(fn draw-lite [col row]
	;get lite state to know which sprite
	(local blvl (brite-lvl col row))
	(local tl 
		(. lite-sprites (+ 1 blvl)))
	(local mset 
		(mset-offset 
			(+ (* 2 (- col 1)) field-x)
			(+ (* 2 (- row 1)) field-y)))	
	
	(mset 0 0 tl)
	(mset 1 0 (+ 1 tl))
	(mset 0 1 (+ sprite-below-off tl))
	(mset 1 1
		(+ sprite-below-off (+ 1 tl)))
)
							
(fn draw-field []
 (for [row 1 field-h]
  (for [col 1 field-w]
  	(draw-lite col row)))
)

(fn clamp [lo hi val]
	(if (<= val lo) lo
	    (>= val hi) hi
					val)
)

	
(fn which-bit [col row]
	"returns the index of the bit that 
	corresponds to the desired light."
	(+ (* (- row 1) field-w) (- col 1))
)		

(fn one-lite-bit [col row]
	"returns a bitvect with a single bit
	set in the position of the given light"
	(lshift 1 (which-bit col row))
)

(fn get-lite [col row]
 "returns 1 if the given light is 0,
 zero otherwise."
 (if
		(not= 0 (band lite-state 
			(one-lite-bit col row)))
		1 0)
)
						
(fn toggle-one-lite [col row]
	"toggles a single light at given 
		light coordinates."
	(when 
		(and (>= col 1) (<= col field-w)
			(>= row 1) (<= row field-h))
		(set lite-state 
			(bxor lite-state 
				(one-lite-bit col row)))) 	
)
 	

(fn toggle-lights [col row]
 "toggles lights according to the pattern."
	(toggle-one-lite (- col 1) (- row 1))
	;(toggle-one-lite col (- row 1))
	(toggle-one-lite (+ col 1) (- row 1))
	;(toggle-one-lite (- col 1) row)
	(toggle-one-lite col row)
	;(toggle-one-lite (+ col 1) row)
	(toggle-one-lite (- col 1) (+ row 1))
	;(toggle-one-lite col (+ row 1))
	(toggle-one-lite (+ col 1) (+ row 1))
)

(fn tick-mouse []
	"update the mouse clicked state"
	; old states
	(local [_ _ oldl oldm oldr] last-mouse) 
	; new states
	(local mouse-state (table.pack (mouse)))
	(local [_ _ newl newm newr] mouse-state)
	 
	; the mouse went down only if it was
	; up (false) and is now down (true)
	(tset mouse-went-down 1 
		(and (not oldl) newl)) 
	(tset mouse-went-down 2
		(and (not oldm) newm))
	(tset mouse-went-down 3
		(and (not oldm) newr))
	
	(set last-mouse mouse-state)
)

(fn lmouse-went-down? []
	(. mouse-went-down 1))

(fn tick-lite-brightnesses []
	(for [row 1 field-h]
		(for [col 1 field-w]
			(local state (get-lite col row))
			(local brightness 
				(. brite-state row col))
			(local target (* state fully-on))
			(local direction
				(if (< brightness target) 1
				    (= brightness target) 0
								 -1))
			(local delta (* direction ms-per-tick))
			(local new-brightness
				(clamp fully-off fully-on
					(+ brightness delta)))
			(tset brite-state 
				row col new-brightness)))
)

(fn hint [board-state solution]
	"scans solution for the first [col row] 
	that differs from the current board 
	state or nil if already solved."
	(local difference 
		(bxor choices solution))
	(if (= 0 difference) nil
		(do
			(var shift 0)
			(while (not= 1
				(band (rshift difference shift) 1))
					(inc! shift))
			[(+ 1 (% shift field-w)) 
				(+ 1 (// shift field-h))]))
)	

(fn clear-play-area-tiles []
	(for [col 12 29]
		(for [row 0 16]
			(mset col row 0)))
)
				
(fn clear-state []
	(clear-play-area-tiles)

	(set lite-state 0xFFFFFFFFFFFFFFFF)
	(set solution 0)
	(set choices 0)
	(set game-won false)
	(set showing-hint false)
	; todo: field w and h
	; todo: gui params
)

(fn win-game []
	(set game-won true)
	(music 0 0 0 false)
)

(fn won-game? []
	(= choices solution))
				
(fn new-game [diff seed ncols nrows]
	"start a new game with a given
	 difficulty (in number of moves) and
		seed."
	(music 1 0 0 false)
	(math.randomseed seed)
	(set current-seed seed)
	
	(clear-state)
	
	(set field-w ncols)
	(set field-h nrows)
	
	; I could generate a random solution
	; vector and use that. maybe future.
	(for [i 1 diff] 
		(local col (math.random 1 field-w))
		(local row (math.random 1 field-h))
		(set solution
			(bxor solution 
				(one-lite-bit col row)))
		(toggle-lights col row))
)

(fn print-buttons []
	(print "New Game:" 0 96 12) 
	(print "3x3" 
		(+ ng3x3-x 4) (+ ng3x3-y 1) 12)
	(print "4x4" 
		(+ ng4x4-x 4) (+ ng4x4-y 1) 12)
	(print "5x5"
		(+ ng5x5-x 4) (+ ng5x5-y 1) 12)
	(print "6x6"
		(+ ng6x6-x 4) (+ ng6x6-y 1) 12)
	(print "7x7"
	 (+ ng7x7-x 4) (+ ng7x7-y 1) 12)
	(print "8x8" 
	 (+ ng8x8-x 4) (+ ng8x8-y 1) 12)
	(print "Reset Game"
	 (+ reset-x 8) (+ reset-y 1) 12)
	(print "Hint"
		(+ hintbtn-x 6) (+ hintbtn-y 1) 12)
)

(fn gen-seed []
	(math.random seed-min seed-max))

(fn _G.TEST [])

(fn _G.BOOT []
	(music) 
	(new-game difficulty 123 8 8)
	(draw-field)
)

(fn _G.TIC [] 
	(tick-lite-brightnesses)
	(draw-field) ; opt: could be conditional
	(map)
	
	(tick-mouse)
	
	(local where (where-pix (mouse)))
 (local which (which-lite (mouse)))
 (when which 
 	(local [col row] which)
 	(when (. mouse-went-down 1)
  	(toggle-lights col row)
   (set showing-hint false)
   (set choices ; record choice
   	(bxor choices 
   		(one-lite-bit col row)))
   (sfx 0 24 64))
   
  (print 
  	(.. "Location: " col ", " row) 0 8 12)
 )
 (local diff difficulty)
 (when (. mouse-went-down 1)
 	(case where
  	"hint"
    (set showing-hint true)
 		"ng3x3"				
   	(new-game diff (gen-seed) 3 3)
   "ng4x4"
   	(new-game diff (gen-seed) 4 4)
		 "ng5x5"
				(new-game diff (gen-seed) 5 5)
			"ng6x6"
				(new-game diff (gen-seed) 6 6)
			"ng7x7"
				(new-game diff (gen-seed) 7 7)
			"ng8x8"
			 (new-game diff (gen-seed) 8 8)
			"reset"
				(new-game diff current-seed field-w field-h)
		)
	)
 (when 
 	(and
 		(not game-won)
 		(won-game?)) 
  (win-game))
  
 (when game-won
 	(print "You win!" 0 44 12)) 
   
 (local a-hint (hint lite-state solution))
 (when (and a-hint showing-hint) 
 	(let [col (. a-hint 1)
        row (. a-hint 2)]
   (print (string.format "Try: %d, %d"
   	 col row) 0 24 12)))
   
 (print-buttons)
 
 
 (print (.. "seed: " current-seed)
  	0 130 12)
)
		
		
		
		
	