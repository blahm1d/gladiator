focus :sub
wpi 21,1,w,wpdata==f0
g
printf "SOUND,F0,%04X\n",pc
focus :csnd
printf "CSND,AT_F0,%03X\n",pc
quit
