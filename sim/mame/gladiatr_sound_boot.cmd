focus :sub
do temp0=0
trace sim/out/mame-sound.tr,:sub,noloop,{do temp0=temp0+1}
wp 8000,400,w,1,{printf "BUS,sound,mem_w,%04X,%02X\n",wpaddr,wpdata ; g}
wpi 0,100,w,1,{printf "BUS,sound,io_w,%04X,%02X\n",wpaddr,wpdata ; g}
rp {temp0>=#10000},{traceflush;quit}
g
