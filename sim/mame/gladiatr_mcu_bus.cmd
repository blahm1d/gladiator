focus :maincpu
do temp0=0
wpi c09e,2,r,1,{printf "UCPU,R,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; do temp0=temp0+1 ; g}
wpi c09e,2,w,1,{printf "UCPU,W,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; do temp0=temp0+1 ; g}
rp {temp0>=#80},{quit}
g
