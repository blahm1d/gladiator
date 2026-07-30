focus :sub
do temp0=0
wpi 20,2,r,1,{printf "CSND,R,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; do temp0=temp0+1 ; g}
wpi 20,2,w,1,{printf "CSND,W,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; do temp0=temp0+1 ; g}
rp {temp0>=#40},{quit}
g
