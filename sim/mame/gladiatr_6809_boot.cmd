focus :audiocpu
do temp0=0
trace sim/out/mame-6809.tr,:audiocpu,noloop,{do temp0=temp0+1}
wp 1000,1000,w,1,{printf "BUS,6809,mem_w,%04X,%02X\n",wpaddr,wpdata ; g}
rp {temp0>=#10000},{traceflush;quit}
g
