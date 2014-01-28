#!/bin/bash

## partition disk; single physical partition
sfdisk /dev/xvdj << EOF
0,,83,*
;
;
;
EOF

time dd if=my-image-name.img of=/dev/xvdj1 bs=8M
e2fsck -f /dev/xvdj1
resize2fs /dev/xvdj1
