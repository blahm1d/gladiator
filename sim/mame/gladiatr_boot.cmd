focus :maincpu
do temp0=0
trace sim/out/mame-main.tr,:maincpu,noloop,{do temp0=temp0+1}
wp c000,3800,w,1,{printf "BUS,main,mem_w,%04X,%02X\n",wpaddr,wpdata ; g}
wpi c000,100,w,1,{printf "BUS,main,io_w,%04X,%02X\n",wpaddr,wpdata ; g}
rp {temp0>=#10000},{traceflush;quit}
g
