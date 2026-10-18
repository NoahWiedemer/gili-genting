#!/usr/bin/env python3
"""
Gili Genting - pixel font generator.

Builds two original pixel-art TrueType fonts from hand-drawn bitmaps below:

  GiliPixel.ttf  main UI / dialog font
                 unitsPerEm 1000, 1 px = 100 units  -> pixel perfect at 10/20/30/40 px
                 ascent 8 px, descent 2 px, cap height 7, x-height 5
  GiliTitle.ttf  chunky slab-serif display font (titles, logo, banners)
                 unitsPerEm 1400, 1 px = 100 units  -> pixel perfect at 14/28/42 px
                 ascent 12 px, descent 2 px, cap height 11, small caps 8

Every glyph is a set of square pixels. Adjacent pixels are merged into clean
axis-aligned outlines (clockwise outer contours, counter-clockwise holes), so
there are no seams or overlaps.

Usage:  python3 tools/gen_fonts.py          (builds fonts + preview PNGs)

Bitmap format: a header line "=X [top=N]" where X is the character itself or
U+XXXX, followed by rows of '.'/'#' from top to bottom. `top` is the pixel row
(baseline = row 0, rows above baseline positive) of the first bitmap line.
The advance width is bitmap width + 1 px letter spacing.
"""
import os
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.agl import UV2AGL
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "game", "assets", "fonts")
PREVIEW_DIR = os.path.join(ROOT, "art_src")
PX = 100  # font units per design pixel

# ---------------------------------------------------------------------------
# GiliPixel - main font. Default top row = 6 (cap height 7: rows 6..0).
# ---------------------------------------------------------------------------
MAIN = r"""
=U+FFFF top=6
#####
#...#
#.#.#
#...#
#.#.#
#...#
#####

=A
.###.
#...#
#...#
#####
#...#
#...#
#...#

=B
####.
#...#
#...#
####.
#...#
#...#
####.

=C
.###.
#...#
#....
#....
#....
#...#
.###.

=D
###..
#..#.
#...#
#...#
#...#
#..#.
###..

=E
#####
#....
#....
####.
#....
#....
#####

=F
#####
#....
#....
####.
#....
#....
#....

=G
.###.
#...#
#....
#.###
#...#
#...#
.####

=H
#...#
#...#
#...#
#####
#...#
#...#
#...#

=I
###
.#.
.#.
.#.
.#.
.#.
###

=J
..###
...#.
...#.
...#.
#..#.
#..#.
.##..

=K
#...#
#..#.
#.#..
##...
#.#..
#..#.
#...#

=L
#....
#....
#....
#....
#....
#....
#####

=M
#.....#
##...##
#.#.#.#
#..#..#
#.....#
#.....#
#.....#

=N
#...#
#...#
##..#
#.#.#
#..##
#...#
#...#

=O
.###.
#...#
#...#
#...#
#...#
#...#
.###.

=P
####.
#...#
#...#
####.
#....
#....
#....

=Q
.###.
#...#
#...#
#...#
#.#.#
#..#.
.##.#

=R
####.
#...#
#...#
####.
#.#..
#..#.
#...#

=S
.###.
#...#
#....
.###.
....#
#...#
.###.

=T
#####
..#..
..#..
..#..
..#..
..#..
..#..

=U
#...#
#...#
#...#
#...#
#...#
#...#
.###.

=V
#...#
#...#
#...#
#...#
.#.#.
.#.#.
..#..

=W
#.....#
#.....#
#.....#
#..#..#
#.#.#.#
##...##
#.....#

=X
#...#
#...#
.#.#.
..#..
.#.#.
#...#
#...#

=Y
#...#
#...#
.#.#.
..#..
..#..
..#..
..#..

=Z
#####
....#
...#.
..#..
.#...
#....
#####

=U+00C4 top=7
.#.#.
.....
.###.
#...#
#...#
#####
#...#
#...#

=U+00D6 top=7
.#.#.
.....
.###.
#...#
#...#
#...#
#...#
.###.

=U+00DC top=7
.#.#.
.....
#...#
#...#
#...#
#...#
#...#
.###.

=a top=4
.##.
...#
.###
#..#
.###

=b
#...
#...
###.
#..#
#..#
#..#
###.

=c top=4
.##.
#..#
#...
#..#
.##.

=d
...#
...#
.###
#..#
#..#
#..#
.###

=e top=4
.##.
#..#
####
#...
.###

=f
.##
#..
###
#..
#..
#..
#..

=g top=4
.###
#..#
#..#
#..#
.###
...#
.##.

=h
#...
#...
###.
#..#
#..#
#..#
#..#

=i
#
.
#
#
#
#
#

=j
..#
...
..#
..#
..#
..#
..#
..#
##.

=k
#...
#...
#..#
#.#.
##..
#.#.
#..#

=l
#.
#.
#.
#.
#.
#.
.#

=m top=4
##.#.
#.#.#
#.#.#
#.#.#
#.#.#

=n top=4
###.
#..#
#..#
#..#
#..#

=o top=4
.##.
#..#
#..#
#..#
.##.

=p top=4
###.
#..#
#..#
#..#
###.
#...
#...

=q top=4
.###
#..#
#..#
#..#
.###
...#
...#

=r top=4
#.##
##..
#...
#...
#...

=s top=4
.###
#...
.##.
...#
###.

=t top=5
.#.
###
.#.
.#.
.#.
..#

=u top=4
#..#
#..#
#..#
#..#
.###

=v top=4
#...#
#...#
.#.#.
.#.#.
..#..

=w top=4
#...#
#...#
#.#.#
#.#.#
.#.#.

=x top=4
#...#
.#.#.
..#..
.#.#.
#...#

=y top=4
#..#
#..#
#..#
#..#
.###
...#
.##.

=z top=4
####
...#
.##.
#...
####

=U+00E4
#..#
....
.##.
...#
.###
#..#
.###

=U+00F6
#..#
....
.##.
#..#
#..#
#..#
.##.

=U+00FC
#..#
....
#..#
#..#
#..#
#..#
.###

=U+00DF
.##.
#..#
#..#
#.#.
#..#
#..#
#.#.

=0
.###.
#...#
#..##
#.#.#
##..#
#...#
.###.

=1
..#..
.##..
..#..
..#..
..#..
..#..
.###.

=2
.###.
#...#
....#
...#.
..#..
.#...
#####

=3
.###.
#...#
....#
..##.
....#
#...#
.###.

=4
...#.
..##.
.#.#.
#..#.
#####
...#.
...#.

=5
#####
#....
####.
....#
....#
#...#
.###.

=6
..##.
.#...
#....
####.
#...#
#...#
.###.

=7
#####
....#
...#.
..#..
..#..
..#..
..#..

=8
.###.
#...#
#...#
.###.
#...#
#...#
.###.

=9
.###.
#...#
#...#
.####
....#
...#.
.##..

=!
#
#
#
#
#
.
#

="
#.#
#.#

=#
.#.#.
.#.#.
#####
.#.#.
#####
.#.#.
.#.#.

=$
..#..
.####
#.#..
.###.
..#.#
####.
..#..

=%
##..#
##.#.
...#.
..#..
.#...
.#.##
#..##

=&
.##..
#..#.
#.#..
.#...
#.#.#
#..#.
.##.#

='
#
#

=(
..#
.#.
#..
#..
#..
.#.
..#

=)
#..
.#.
..#
..#
..#
.#.
#..

=* top=5
..#..
#.#.#
.###.
#.#.#
..#..

=+ top=5
..#..
..#..
#####
..#..
..#..

=, top=0
.#
#.

=- top=3
###

=. top=0
#

=/
..#
..#
.#.
.#.
.#.
#..
#..

=: top=3
#
.
.
#

=; top=3
.#
..
..
.#
#.

=< top=5
...#
.##.
#...
.##.
...#

=U+003D top=4
####
....
####

=> top=5
#...
.##.
...#
.##.
#...

=?
.###.
#...#
....#
...#.
..#..
.....
..#..

=@
.###.
#...#
#.###
#.#.#
#.###
#....
.###.

=[
##
#.
#.
#.
#.
#.
##

=\
#..
#..
.#.
.#.
.#.
..#
..#

=]
##
.#
.#
.#
.#
.#
##

=^
.#.
#.#

=_ top=-1
#####

=`
#.
.#

={
..#
.#.
.#.
#..
.#.
.#.
..#

=|
#
#
#
#
#
#
#
#

=}
#..
.#.
.#.
..#
.#.
.#.
#..

=~ top=4
.##.#
#..#.

=U+201E top=0
.#.#
#.#.

=U+201C
.#.#
#.#.
#.#.

=U+201D
.#.#
.#.#
#.#.

=U+201A top=0
.#
#.

=U+2018
.#
#.
#.

=U+2019
.#
.#
#.

=U+00AB top=3
.#.#
#.#.
.#.#

=U+00BB top=3
#.#.
.#.#
#.#.

=U+2013 top=3
#####

=U+2014 top=3
#########

=U+2026 top=0
#.#.#

=U+2022 top=4
###
###
###

=U+00B7 top=3
#

=U+20AC
..###
.#...
####.
.#...
####.
.#...
..###

=U+00B0
.#.
#.#
.#.

=U+00D7 top=4
#.#
.#.
#.#

=U+00F7 top=5
..#..
.....
#####
.....
..#..

=U+00B1 top=5
..#..
#####
..#..
.....
#####

=U+00BD
#....#.
#...#..
#..#...
..#.##.
.#....#
#....#.
....###

=U+00B4
.#
#.

=U+2665
.##.##.
#######
#######
.#####.
..###..
...#...

=U+2605
...#...
..###..
#######
.#####.
..###..
.##.##.
.#...#.

=U+2606
...#...
..#.#..
##...##
.#...#.
..#.#..
.#.#.#.
.#...#.

=U+25B6
#...
##..
###.
####
###.
##..
#...

=U+25C0
...#
..##
.###
####
.###
..##
...#

=U+25B2 top=5
...#...
..###..
.#####.
#######

=U+25BC top=5
#######
.#####.
..###..
...#...

=U+266A
..##.
..#.#
..#..
..#..
..#..
###..
##...

=U+2620
.#####.
#######
#..#..#
#..#..#
###.###
.#####.
.#.#.#.

=U+2694
#.....#
.#...#.
..#.#..
...#...
..#.#..
##...##
##...##

=U+271A
..###..
..###..
#######
#######
#######
..###..
..###..

=U+25C6
...#...
..###..
.#####.
#######
.#####.
..###..
...#...

=U+2726
...#...
...#...
..###..
#######
..###..
...#...
...#...

=U+2192 top=5
...#..
....#.
######
....#.
...#..

=U+2190 top=5
..#...
.#....
######
.#....
..#...

=U+2191
..#..
.###.
#.#.#
..#..
..#..
..#..
..#..

=U+2193
..#..
..#..
..#..
..#..
#.#.#
.###.
..#..
"""

# ---------------------------------------------------------------------------
# GiliTitle - display font. Default top row = 10 (cap height 11: rows 10..0).
# Lowercase letters are small caps, 8 px tall (top=7).
# ---------------------------------------------------------------------------
TITLE = r"""
=U+FFFF
########
########
##....##
##....##
##....##
##....##
##....##
##....##
##....##
########
########

=A
...####...
..######..
..##..##..
..##..##..
.##....##.
.##....##.
.########.
.########.
.##....##.
.##....##.
####..####

=B
#######..
.#######.
.##...##.
.##...##.
.#######.
.########
.##....##
.##....##
.##....##
.########
########.

=C
..######.
.########
###....##
##.......
##.......
##.......
##.......
##.......
###....##
.########
..######.

=D
#######..
.########
.##...###
.##....##
.##....##
.##....##
.##....##
.##....##
.##...###
.########
#######..

=E
########
.#######
.##....#
.##.....
.######.
.######.
.##.....
.##.....
.##....#
.#######
########

=F
########
.#######
.##....#
.##.....
.######.
.######.
.##.....
.##.....
.##.....
.##.....
####....

=G
..######.
.########
###....##
##.......
##.......
##..#####
##..#####
##.....##
###....##
.########
..######.

=H
####..####
.##....##.
.##....##.
.##....##.
.########.
.########.
.##....##.
.##....##.
.##....##.
.##....##.
####..####

=I
####
.##.
.##.
.##.
.##.
.##.
.##.
.##.
.##.
.##.
####

=J
....####
.....##.
.....##.
.....##.
.....##.
.....##.
.....##.
##...##.
##...##.
.######.
..####..

=K
####..####
.##....##.
.##...##..
.##..##...
.##.##....
.#####....
.######...
.##..##...
.##...##..
.##....##.
####..####

=L
####....
.##.....
.##.....
.##.....
.##.....
.##.....
.##.....
.##.....
.##....#
.#######
########

=M
####....####
.###....###.
.####..####.
.##.####.##.
.##..##..##.
.##......##.
.##......##.
.##......##.
.##......##.
.##......##.
####....####

=N
###...####
.##....##.
.###...##.
.####..##.
.##.##.##.
.##..####.
.##...###.
.##....##.
.##....##.
.##....##.
####..####

=O
..#####..
.#######.
###...###
##.....##
##.....##
##.....##
##.....##
##.....##
###...###
.#######.
..#####..

=P
#######..
.########
.##....##
.##....##
.##....##
.########
.#######.
.##......
.##......
.##......
####.....

=Q
..#####..
.#######.
###...###
##.....##
##.....##
##.....##
##.....##
##..##.##
###..####
.#######.
..#######
.......##

=R
#######...
.########.
.##....##.
.##....##.
.##....##.
.########.
.#######..
.##..##...
.##...##..
.##....##.
####...###

=S
..######.
.########
##.....##
##.......
.######..
..######.
.......##
.......##
##.....##
########.
.######..

=T
##########
##########
#...##...#
....##....
....##....
....##....
....##....
....##....
....##....
....##....
...####...

=U
####..####
.##....##.
.##....##.
.##....##.
.##....##.
.##....##.
.##....##.
.##....##.
.###..###.
..######..
...####...

=V
####..####
.##....##.
.##....##.
.##....##.
..##..##..
..##..##..
..##..##..
...####...
...####...
....##....
....##....

=W
####....####
.##......##.
.##......##.
.##......##.
.##......##.
.##......##.
.##..##..##.
.##.####.##.
.####..####.
.###....###.
.##......##.

=X
####..####
.##....##.
.##....##.
..##..##..
...####...
....##....
...####...
..##..##..
.##....##.
.##....##.
####..####

=Y
####..####
.##....##.
.##....##.
..##..##..
...####...
....##....
....##....
....##....
....##....
....##....
...####...

=Z
#########
#########
#.....###
.....###.
....###..
...###...
..###....
.###.....
###.....#
#########
#########

=U+00C4 top=11
..##..##..
..##..##..
..........
...####...
..##..##..
.##....##.
.##....##.
.########.
.########.
.##....##.
.##....##.
####..####

=U+00D6 top=11
.##...##.
.##...##.
.........
..#####..
.#######.
###...###
##.....##
##.....##
##.....##
###...###
.#######.
..#####..

=U+00DC top=11
..##..##..
..##..##..
..........
####..####
.##....##.
.##....##.
.##....##.
.##....##.
.##....##.
.###..###.
..######..
...####...

=a top=7
..####..
.######.
.##..##.
.##..##.
.######.
.######.
.##..##.
###..###

=b top=7
######..
.######.
.##..##.
.#####..
.######.
.##..##.
.######.
######..

=c top=7
..#####
.######
###...#
##.....
##.....
###...#
.######
..#####

=d top=7
######..
.######.
.##..###
.##...##
.##...##
.##..###
.######.
######..

=e top=7
#######
.######
.##...#
.####..
.####..
.##...#
.######
#######

=f top=7
#######
.######
.##...#
.####..
.####..
.##....
.##....
####...

=g top=7
..#####.
.#######
###.....
##..####
##..####
###...##
.#######
..#####.

=h top=7
###..###
.##..##.
.##..##.
.######.
.######.
.##..##.
.##..##.
###..###

=i top=7
####
.##.
.##.
.##.
.##.
.##.
.##.
####

=j top=7
...####
....##.
....##.
....##.
....##.
##..##.
.#####.
..###..

=k top=7
###..###
.##..##.
.##.##..
.####...
.####...
.##.##..
.##..##.
###..###

=l top=7
####...
.##....
.##....
.##....
.##....
.##...#
.######
#######

=m top=7
###....###
.###..###.
.########.
.##.##.##.
.##....##.
.##....##.
.##....##.
###....###

=n top=7
###..###
.##..##.
.###.##.
.######.
.##.###.
.##..##.
.##..##.
###..###

=o top=7
..####..
.######.
###..###
##....##
##....##
###..###
.######.
..####..

=p top=7
######..
.######.
.##..##.
.##..##.
.######.
.#####..
.##.....
####....

=q top=7
..####..
.######.
###..###
##....##
##.##.##
###.####
.######.
..######
......##

=r top=7
######..
.######.
.##..##.
.##..##.
.######.
.####...
.##.##..
###..###

=s top=7
.######
#######
##.....
######.
.######
.....##
#######
######.

=t top=7
########
########
#..##..#
...##...
...##...
...##...
...##...
..####..

=u top=7
###..###
.##..##.
.##..##.
.##..##.
.##..##.
.##..##.
.######.
..####..

=v top=7
###..###
.##..##.
.##..##.
.##..##.
..####..
..####..
...##...
...##...

=w top=7
###....###
.##....##.
.##....##.
.##....##.
.##.##.##.
.########.
.###..###.
.##....##.

=x top=7
###..###
.##..##.
..####..
...##...
...##...
..####..
.##..##.
###..###

=y top=7
###..###
.##..##.
.##..##.
..####..
...##...
...##...
...##...
..####..

=z top=7
#######
#######
....###
...###.
..###..
.###...
#######
#######

=U+00E4 top=10
.##..##.
.##..##.
........
..####..
.######.
.##..##.
.##..##.
.######.
.######.
.##..##.
###..###

=U+00F6 top=10
.##..##.
.##..##.
........
..####..
.######.
###..###
##....##
##....##
###..###
.######.
..####..

=U+00FC top=10
.##..##.
.##..##.
........
###..###
.##..##.
.##..##.
.##..##.
.##..##.
.##..##.
.######.
..####..

=U+00DF
.######..
########.
##....##.
##...##..
##..##...
##..####.
##.....##
##.....##
##.....##
##.#####.
##.####..

=0
..####..
.######.
###..###
##....##
##....##
##....##
##....##
##....##
###..###
.######.
..####..

=1
..##..
.###..
####..
..##..
..##..
..##..
..##..
..##..
..##..
..##..
######

=2
.######.
########
##....##
......##
.....###
...####.
..###...
.###....
###.....
########
########

=3
.######.
########
##....##
......##
...####.
...####.
......##
......##
##....##
########
.######.

=4
....###.
...####.
..##.##.
.##..##.
##...##.
########
########
.....##.
.....##.
.....##.
....####

=5
########
########
##......
##......
#######.
########
......##
......##
##....##
########
.######.

=6
..#####.
.######.
###.....
##......
#######.
########
##....##
##....##
###..###
.######.
..####..

=7
########
########
##....##
.....##.
.....##.
....##..
....##..
...##...
...##...
...##...
..####..

=8
.######.
########
##....##
##....##
.######.
.######.
##....##
##....##
##....##
########
.######.

=9
..####..
.######.
###..###
##....##
##....##
########
.#######
......##
.....###
.######.
.#####..

=. top=1
##
##

=, top=1
##
##
.#
#.

=!
##
##
##
##
##
##
##
##
..
##
##

=?
.######.
########
##....##
......##
.....###
...####.
...###..
...##...
........
...##...
...##...

=: top=6
##
##
..
..
..
##
##

=; top=6
##
##
..
..
..
##
##
.#
#.

=- top=5
#####
#####

='
##
##
##

="
##.##
##.##
##.##

=(
..##
.##.
##..
##..
##..
##..
##..
##..
##..
.##.
..##

=)
##..
.##.
..##
..##
..##
..##
..##
..##
..##
.##.
##..

=&
..####....
.######...
.##..##...
.##.##....
..###.....
.####..##.
##.###.##.
##..####..
##...###..
.########.
..####.###

=/
....##
....##
...##.
...##.
..##..
..##..
.##...
.##...
##....
##....
##....

=U+2026 top=1
##.##.##
##.##.##

=U+2013 top=5
########
########

=U+2014 top=5
############
############

=U+201E top=1
##.##
##.##
.#..#
#..#.

=U+201C
.#..#
#..#.
##.##
##.##

=U+201D
##.##
##.##
.#..#
#..#.

=U+2018
.#
#.
##
##

=U+2019
##
##
.#
#.

=U+2665 top=9
.###...###.
#####.#####
###########
###########
###########
.#########.
..#######..
...#####...
....###....
.....#.....

=U+2605
.....#.....
....###....
....###....
###########
.#########.
..#######..
...#####...
..#######..
..###.###..
.###...###.
.##.....##.
"""


# ---------------------------------------------------------------------------
# Parsing and outline tracing
# ---------------------------------------------------------------------------
def parse_glyphs(src, default_top):
    glyphs = {}
    cur = None

    def flush():
        if cur is None:
            return
        rows = cur["rows"]
        assert rows, "glyph U+%04X has no rows" % cur["cp"]
        widths = {len(r) for r in rows}
        assert len(widths) == 1, "glyph U+%04X has ragged rows %r" % (cur["cp"], widths)
        width = widths.pop()
        pixels = set()
        for i, row in enumerate(rows):
            y = cur["top"] - i
            for x, c in enumerate(row):
                if c == "#":
                    pixels.add((x, y))
        assert cur["cp"] not in glyphs, "duplicate glyph U+%04X" % cur["cp"]
        glyphs[cur["cp"]] = {"width": width, "pixels": pixels}

    for raw in src.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("="):
            flush()
            parts = line[1:].split()
            key = parts[0]
            cp = int(key[2:], 16) if (key.startswith("U+") and len(key) > 2) else ord(key)
            top = default_top
            for p in parts[1:]:
                if p.startswith("top="):
                    top = int(p[4:])
            cur = {"cp": cp, "top": top, "rows": []}
        else:
            assert set(line) <= set(".#"), "bad row %r" % line
            cur["rows"].append(line)
    flush()
    return glyphs


def trace(pixels):
    """Return merged outline contours (lists of (x, y) in pixel units, y up).

    Each boundary edge is directed so the filled pixel is on its right, which
    yields clockwise outer contours and counter-clockwise holes (TrueType
    convention). At diagonal touch points the sharpest right turn is taken so
    diagonally-touching pixels stay separate contours (no self-intersection).
    """
    out = {}

    def add(a, b):
        out.setdefault(a, []).append(b)

    for (x, y) in pixels:
        if (x - 1, y) not in pixels:
            add((x, y), (x, y + 1))
        if (x, y + 1) not in pixels:
            add((x, y + 1), (x + 1, y + 1))
        if (x + 1, y) not in pixels:
            add((x + 1, y + 1), (x + 1, y))
        if (x, y - 1) not in pixels:
            add((x + 1, y), (x, y))

    simple_starts = sorted(k for k, v in out.items() if len(v) == 1)
    contours = []
    while True:
        start = next((s for s in simple_starts if out.get(s)), None)
        if start is None:
            rest = sorted(k for k, v in out.items() if v)
            if not rest:
                break
            start = rest[0]
        pts = [start]
        cur = out[start].pop()
        d = (cur[0] - start[0], cur[1] - start[1])
        guard = 0
        while cur != start:
            pts.append(cur)
            cands = out[cur]
            if len(cands) == 1:
                nxt = cands.pop()
            else:
                right = (d[1], -d[0])
                straight = d
                left = (-d[1], d[0])
                nxt = None
                for want in (right, straight, left):
                    for c in cands:
                        if (c[0] - cur[0], c[1] - cur[1]) == want:
                            nxt = c
                            break
                    if nxt:
                        break
                cands.remove(nxt)
            d = (nxt[0] - cur[0], nxt[1] - cur[1])
            cur = nxt
            guard += 1
            assert guard < 100000
        # drop collinear points
        n = len(pts)
        simp = []
        for i in range(n):
            p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
            d1 = (p1[0] - p0[0], p1[1] - p0[1])
            d2 = (p2[0] - p1[0], p2[1] - p1[1])
            if d1[0] * d2[1] - d1[1] * d2[0] != 0:
                simp.append(p1)
        contours.append(simp)
    return contours


def glyph_name(cp):
    if cp == 0xFFFF:
        return ".notdef"
    if cp in UV2AGL:
        return UV2AGL[cp]
    return "uni%04X" % cp


# ---------------------------------------------------------------------------
# Font building
# ---------------------------------------------------------------------------
def build_font(spec):
    glyph_bitmaps = parse_glyphs(spec["src"], spec["default_top"])
    notdef = glyph_bitmaps.pop(0xFFFF)

    order = [".notdef", "space"]
    cmap = {0x20: "space", 0xA0: "space"}
    advances = {".notdef": (notdef["width"] + 1) * PX, "space": spec["space"] * PX}
    pens = {}

    def draw(name, bm):
        pen = TTGlyphPen(None)
        for contour in trace(bm["pixels"]):
            pen.moveTo((contour[0][0] * PX, contour[0][1] * PX))
            for (x, y) in contour[1:]:
                pen.lineTo((x * PX, y * PX))
            pen.closePath()
        pens[name] = pen.glyph()

    draw(".notdef", notdef)
    pens["space"] = TTGlyphPen(None).glyph()

    for cp in sorted(glyph_bitmaps):
        bm = glyph_bitmaps[cp]
        name = glyph_name(cp)
        order.append(name)
        cmap[cp] = name
        advances[name] = (bm["width"] + 1) * PX
        draw(name, bm)

    # convenience aliases
    for alias, target in spec.get("aliases", {}).items():
        if target in cmap and alias not in cmap:
            cmap[alias] = cmap[target]

    asc, desc = spec["ascent"] * PX, spec["descent"] * PX
    fb = FontBuilder(spec["upem"], isTTF=True)
    fb.setupHead(unitsPerEm=spec["upem"], fontRevision=1.0,
                 created=fb.font["head"].created, modified=fb.font["head"].modified)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(pens)
    glyf = fb.font["glyf"]
    metrics = {}
    for name in order:
        g = glyf[name]
        lsb = g.xMin if getattr(g, "numberOfContours", 0) else 0
        metrics[name] = (advances[name], lsb)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=asc, descent=-desc, lineGap=0)
    family = spec["family"]
    ps = family.replace(" ", "") + "-Regular"
    fb.setupNameTable({
        "copyright": "Original pixel font for Gili Genting. (c) 2026 Gili Genting project.",
        "familyName": family,
        "styleName": "Regular",
        "uniqueFontIdentifier": "1.000;GILI;" + ps,
        "fullName": family + " Regular",
        "version": "Version 1.000",
        "psName": ps,
        "manufacturer": "Gili Genting",
        "designer": "Gili Genting",
        "description": spec["description"],
        "typographicFamily": family,
        "typographicSubfamily": "Regular",
    })
    cps = [c for c in cmap if c <= 0xFFFF]
    fb.setupOS2(
        version=4,
        usWeightClass=400,
        usWidthClass=5,
        fsType=0,  # installable embedding
        sTypoAscender=asc,
        sTypoDescender=-desc,
        sTypoLineGap=0,
        usWinAscent=asc,
        usWinDescent=desc,
        sxHeight=spec["xheight"] * PX,
        sCapHeight=spec["capheight"] * PX,
        usDefaultChar=0,
        usBreakChar=0x20,
        usMaxContext=1,
        usFirstCharIndex=min(cps),
        usLastCharIndex=max(cps),
        achVendID="GILI",
        fsSelection=0x40 | 0x80,  # REGULAR | USE_TYPO_METRICS
        ySubscriptXSize=spec["upem"] // 2, ySubscriptYSize=spec["upem"] // 2,
        ySubscriptYOffset=PX * 1, ySuperscriptXSize=spec["upem"] // 2,
        ySuperscriptYSize=spec["upem"] // 2, ySuperscriptYOffset=PX * 4,
        yStrikeoutSize=PX, yStrikeoutPosition=PX * 3,
    )
    fb.font["OS/2"].recalcCodePageRanges(fb.font)
    fb.setupPost(isFixedPitch=0, underlinePosition=-PX, underlineThickness=PX, keepGlyphNames=True)
    # gasp: no grid-fitting / smoothing needed, outlines already sit on the pixel grid
    from fontTools.ttLib import newTable
    gasp = newTable("gasp")
    gasp.version = 1
    gasp.gaspRange = {0xFFFF: 0x000A}  # symmetric smoothing (sizes are pixel exact anyway)
    fb.font["gasp"] = gasp

    path = os.path.join(OUT_DIR, spec["file"])
    fb.save(path)
    return path, glyph_bitmaps


# ---------------------------------------------------------------------------
# Validation + previews
# ---------------------------------------------------------------------------
TEST = ("Gili Genting — Kapitel 1: Der Sturm. Äpfel, Öl, Übermut, Straße! "
        "1234567890 ♥ HP 120/120 ★ „Mach deine Augen zu und fühl's.“")


def wrap_test(n):
    words = TEST.split(" ")
    lines, cur = [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > n:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    lines.append(cur)
    return lines


def validate(path, bitmaps, spec):
    f = TTFont(path)
    cmap = f.getBestCmap()
    missing = [c for c in bitmaps if c not in cmap]
    assert not missing, missing
    head, hhea, os2 = f["head"], f["hhea"], f["OS/2"]
    ymax = max(f["glyf"][g].yMax for g in f.getGlyphOrder() if f["glyf"][g].numberOfContours)
    ymin = min(f["glyf"][g].yMin for g in f.getGlyphOrder() if f["glyf"][g].numberOfContours)
    print("  %s: %d glyphs, upem %d, hhea %d/%d, typo %d/%d, win %d/%d, glyph y-range %d..%d"
          % (os.path.basename(path), len(f.getGlyphOrder()), head.unitsPerEm, hhea.ascent,
             hhea.descent, os2.sTypoAscender, os2.sTypoDescender, os2.usWinAscent,
             os2.usWinDescent, ymin, ymax))
    assert ymax <= os2.usWinAscent and -ymin <= os2.usWinDescent
    # every glyph bitmap distinct
    seen = {}
    for cp, bm in bitmaps.items():
        key = (bm["width"], frozenset(bm["pixels"]))
        seen.setdefault(key, []).append(cp)
    dups = [v for v in seen.values() if len(v) > 1]
    if dups:
        print("  identical bitmaps:", [" ".join(chr(c) for c in d) for d in dups])
    # round-trip through a fresh save to catch compile errors
    import io
    buf = io.BytesIO()
    f.save(buf)
    TTFont(io.BytesIO(buf.getvalue()))["glyf"]


def gray_pixels(path, size, text):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(path, size)
    l, t, r, b = font.getbbox(text)
    img = Image.new("L", (r + 8, size * 2), 0)
    ImageDraw.Draw(img).text((4, size // 2), text, font=font, fill=255)
    hist = img.histogram()
    return sum(hist[1:255]), sum(hist[255:])


def render_preview(path, sizes, wrap_at, extra_lines, out_name, scale_base):
    from PIL import Image, ImageDraw, ImageFont
    bg, fg, sh = (18, 26, 74), (248, 244, 230), (6, 8, 24)
    for size in sizes:
        font = ImageFont.truetype(path, size)
        lines = wrap_test(wrap_at) + [""] + extra_lines
        line_h = size + size // 2
        w = max(font.getbbox(l)[2] if l else 0 for l in lines) + size * 2
        h = line_h * len(lines) + size * 2
        img = Image.new("RGB", (w, h), bg)
        d = ImageDraw.Draw(img)
        d.fontmode = "1"
        y = size
        unit = max(1, size // scale_base)
        for l in lines:
            if l:
                d.text((size + unit, y + unit), l, font=font, fill=sh)
                d.text((size, y), l, font=font, fill=fg)
            y += line_h
        scale = max(1, 40 // size) if size < 40 else 1
        if scale > 1:
            img = img.resize((w * scale, h * scale), Image.NEAREST)
        out = os.path.join(PREVIEW_DIR, "%s_%d.png" % (out_name, size))
        img.save(out)
        print("  preview:", out, img.size)


MAIN_SPEC = dict(
    src=MAIN, default_top=6, file="GiliPixel.ttf", family="Gili Pixel", upem=1000,
    ascent=8, descent=2, capheight=7, xheight=5, space=4,
    description="Gili Pixel - proportional 10px pixel font for the Gili Genting RPG. "
                "Pixel perfect at 10/20/30/40 px.",
    aliases={0x2212: ord("-"), 0x00AD: ord("-"), 0x2010: ord("-"), 0x2011: ord("-"),
             0x2027: 0x00B7, 0x2219: 0x00B7, 0x2764: 0x2665, 0x25BA: 0x25B6, 0x25C4: 0x25C0},
)
TITLE_SPEC = dict(
    src=TITLE, default_top=10, file="GiliTitle.ttf", family="Gili Title", upem=1400,
    ascent=12, descent=2, capheight=11, xheight=8, space=5,
    description="Gili Title - chunky slab-serif pixel display font for the Gili Genting RPG. "
                "Pixel perfect at 14/28/42 px.",
    aliases={0x2212: ord("-")},
)

MAIN_CHARSET = [
    "ABCDEFGHIJKLM NOPQRSTUVWXYZ",
    "abcdefghijklm nopqrstuvwxyz",
    "ÄÖÜäöüß 0123456789 Il1| O0 ' ’ , ‚",
    "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~",
    "„“” ‚‘’ «» – — … • · € ° × ÷ ± ½ ´ `",
    "♥ ★ ☆ ▶ ◀ ▲ ▼ ♪ ☠ ⚔ ✚ ◆ ✦ → ← ↑ ↓",
    "▶ Angriff   Magie   Items   Flucht",
    "Die Sonne brennt. Der Rum ist alle. Wer ist schuld?",
]
TITLE_CHARSET = [
    "GILI GENTING",
    "ABCDEFGHIJKLM",
    "NOPQRSTUVWXYZ",
    "abcdefghijklm",
    "nopqrstuvwxyz",
    "ÄÖÜ äöü ß 0123456789",
    ". , ! ? : ; - ' \" ( ) & / …",
    "Kapitel 3: Rum & Reue",
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for spec, sizes, wrap_at, charset, prev in (
        (MAIN_SPEC, (10, 20, 30), 64, MAIN_CHARSET, "font_preview_main"),
        (TITLE_SPEC, (14, 28), 36, TITLE_CHARSET, "font_preview_title"),
    ):
        path, bitmaps = build_font(spec)
        print("built", path)
        validate(path, bitmaps, spec)
        for s in sizes:
            g, full = gray_pixels(path, s, TEST)
            print("  size %d: %d anti-aliased (gray) px, %d solid px" % (s, g, full))
        render_preview(path, sizes, wrap_at, charset, prev, 10 if spec is MAIN_SPEC else 14)


if __name__ == "__main__":
    main()
