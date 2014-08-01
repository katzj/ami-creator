#!/bin/bash

## @todo check if ami name already exists

set -e
set -u
# set -x

function die() {
    echo "$@"
    exit 1
}

[ $EUID -eq 0 ] || die "must be root"

_basedir="$( cd $( dirname -- $0 )/.. && /bin/pwd )"

cachedir="${_basedir}/cache"
[ -d "${cachedir}" ] || mkdir "${cachedir}"

[ $# -eq 4 -o $# -eq 5 ] || die "usage: $0 <kickstart config file> <ami name> <ebs block device> <ebs vol id> [<virtualization-type>]"

config="$( readlink -f ${1} )"
ami_name="${2}"
block_dev="${3}"
img_target_dev="${block_dev}1"

vol_id="${4}"
virt_type=""
kernel_id="--kernel-id aki-919dcaf8" ## specific to us-east-1!

## http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/block-device-mapping-concepts.html
root_device="/dev/sda"

if [ $# -eq 5 ]; then
    virt_type="--virtualization-type ${5}"

    if [ "${5}" == "hvm" ]; then
        ## kernel id only applies for paravirtualized instances
        kernel_id=""
        
        ## the root device for the block device mapping
        root_device="/dev/xvda"
    fi
fi

echo "executing with..."
echo "config: ${config}"
echo "ami_name: ${ami_name}"
echo "block_dev: ${block_dev}"
echo "vol_id: ${vol_id}"
echo "virt_type: ${virt_type}"
echo "kernel_id: ${kernel_id}"
echo "root_device: ${root_device}"

## A client error (InvalidAMIName.Malformed) occurred when calling the
## RegisterImage operation: AMI names must be between 3 and 128 characters long,
## and may contain letters, numbers, '(', ')', '.', '-', '/' and '_'
if [ ${#ami_name} -lt 3 ] || [ ${#ami_name} -gt 128 ]; then
    echo "illegal length for ami_name; must be >= 3, <= 128"
    exit 1
fi

# if echo $ami_name | egrep -q '[^a-z0-9 ()./_-]' ; then
#     echo "illegal characters in ami_name; must be [a-z0-9 ()./_-]"
#     exit 1
# fi

## change to a well-known directory; doesn't have to make sense, just has to be
## consistent.
cd "$( dirname ${config} )"

name="$( basename $config | sed -r -e 's#\.[^.]+$##g' )"
dest_img="${name}.img"

## check for required programs
which aws >/dev/null 2>&1 || die "need aws"
which curl >/dev/null 2>&1 || die "need curl"
which jq >/dev/null 2>&1 || die "need jq"
which e2fsck >/dev/null 2>&1 || die "need e2fsck"
which resize2fs >/dev/null 2>&1 || die "need resize2fs"
which patch >/dev/null 2>&1 || die "need patch"
rpm -q python-imgcreate >/dev/null 2>&1 || die "need python-imgcreate package"

## the block device must exist
[ -e "${block_dev}" ] || die "${block_dev} does not exist"

## volume should be attached to this instance
my_instance_id="$( curl -s http://169.254.169.254/latest/meta-data/instance-id )"

## set up/verify aws credentials and settings
## http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html
export AWS_DEFAULT_REGION="$( curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's#.$##g' )"
[ -n "${AWS_ACCESS_KEY_ID}" ] || die "AWS_ACCESS_KEY_ID not set"
[ -n "${AWS_SECRET_ACCESS_KEY}" ] || die "AWS_SECRET_ACCESS_KEY not set"

if [ "$( aws ec2 describe-volumes --volume-ids ${vol_id} | jq -r .Volumes[].Attachments[].InstanceId )" != "${my_instance_id}" ]; then
    die "volume ${vol_id} is not attached to this instance!"
fi

## create the image
if [ ! -e "${dest_img}" ]; then
    ${_basedir}/ami_creator/ami_creator.py -c "${config}" -n "${name}"
else
    echo "$dest_img already exists; not recreating"
fi

## ok, this is fucked up.  the dd writing the image to the volume is exiting
## with zero, but the data isn't getting written.  Bringing out the big guns.

## forcibly corrupt the fucker so we know we're not working with stale data
dd if=/dev/zero of=${block_dev} bs=8M count=10 conv=fsync oflag=sync
sync;sync;sync

## partition volume
sfdisk ${block_dev} << EOF
0,,83,*
;
;
;
EOF

## reread partition table
hdparm -z ${block_dev}

## write image to volume
echo "writing image to ${img_target_dev}"
dd if=${dest_img} of=${img_target_dev} conv=fsync oflag=sync bs=8k

## force-check the filesystem; re-write the image if it fails
if ! fsck.ext4 -n -f ${img_target_dev} ; then
    echo "well, that didn't work; trying again"
    dd if=${dest_img} of=${img_target_dev} conv=fsync oflag=sync bs=8k
    fsck.ext4 -n -f ${img_target_dev}
fi

## resize the filesystem
resize2fs ${img_target_dev}

if [ $# -eq 5 ]; then
    if [ "${5}" == "hvm" ]; then
        ## special hvm ami stuff, all about fixing up the bootloader

        # patch grub-install then install grub on the volume
        # https://bugs.archlinux.org/task/30241 for where and why for the patch
        ## https://raw.githubusercontent.com/mozilla/build-cloud-tools/master/ami_configs/centos-6-x86_64-hvm-base/grub-install.diff
        if [ ! -e /sbin/grub-install.orig ]; then
            cp /sbin/grub-install /sbin/grub-install.orig

            ## only patch once
            patch --no-backup-if-mismatch -N -p0 -i ${_basedir}/utils/grub-install.diff /sbin/grub-install
        fi

        # mount the volume so we can install grub and fix the /boot/grub/device.map file (otherwise grub can't find the device even with --recheck)
        vol_mnt="/mnt/ebs_vol"
        mkdir -p ${vol_mnt}
        mount -t ext4 ${img_target_dev} ${vol_mnt}

        # make ${vol_mnt}/boot/grub/device.map with contents "(hd0) ${block_dev}" because otherwise grub-install isn't happy, even with --recheck
        echo "(hd0)    ${block_dev}" > ${vol_mnt}/boot/grub/device.map

        grub-install --root-directory=${vol_mnt} --no-floppy ${block_dev}

        # ok grub is installed, now redo device.map for booting the actual volume... because otherwise this bloody well doesn't work
        sed -i -r "s/^(\(hd0\)\s+\/dev\/)[a-z]+$/\1xvda/" ${vol_mnt}/boot/grub/device.map

        umount ${vol_mnt}
    fi
fi

## create a snapshot of the volume
snap_id=$( aws ec2 create-snapshot --volume-id ${vol_id} --description "root image for ${name}" | jq -r .SnapshotId )

while [ $( aws ec2 describe-snapshots --snapshot-ids ${snap_id} | jq -r .Snapshots[].State ) != "completed" ]; do
    echo "waiting for snapshot ${snap_id} to complete"
    sleep 5
done

## kernel-id hard-coded
## see http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/UserProvidedKernels.html
## fuck me, bash space escaping is a pain in the ass.
image_id=$( \
    aws ec2 register-image \
    ${kernel_id} \
    --architecture x86_64 \
    --name "${ami_name}" \
    --root-device-name ${root_device} \
    --block-device-mappings "[{\"DeviceName\":\"${root_device}\",\"Ebs\":{\"SnapshotId\":\"${snap_id}\",\"VolumeSize\":10}},{\"DeviceName\":\"/dev/sdb\",\"VirtualName\":\"ephemeral0\"}]" \
    ${virt_type} \
    | jq -r .ImageId
)

echo "created AMI with id ${image_id}"
