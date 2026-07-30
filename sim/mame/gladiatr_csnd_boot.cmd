focus :csnd
do temp0=0
trace sim/out/mame-csnd.tr,:csnd,noloop,{do temp0=temp0+1}
rp {temp0>=#10000},{traceflush;quit}
g
