focus :maincpu
wp cc80,1,w,(wpdata & 20)!=0,{printf "FIRST_VIDEO_ENABLE pc=%04X data=%02X\n",pc,wpdata ; time ; quit}
g
