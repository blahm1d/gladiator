focus :maincpu
do temp0=0
rp {temp0>=#20000},{traceflush;quit}
bp 085b,1,{trace sim/out/mame-main-mcu-window.tr,:maincpu,noloop,{do temp0=temp0+1} ; g}
g
