focus :maincpu
observe :ucpu
observe :csnd
bp 08e6,1,{trace sim/out/mame-ucpu-link-window.tr,:ucpu,noloop ; trace sim/out/mame-csnd-link-window.tr,:csnd,noloop ; g}
bp 086b,1,{traceflush ; quit}
g
