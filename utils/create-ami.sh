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

[ $# -eq 4 ] || die "usage: $0 <kickstart config file> <ami name> <ebs block device> <ebs vol id>"

config="$( readlink -f ${1} )"
ami_name="${2}"
block_dev="${3}"
vol_id="${4}"

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

## partition volume
sfdisk ${block_dev} << EOF
0,,83,*
;
;
;
EOF

## write image to volume and resize the filesystem
dd if=${dest_img} of=${block_dev}1 bs=8M
e2fsck -f ${block_dev}1
resize2fs ${block_dev}1

## create a snapshot of the volume
snap_id=$( aws ec2 create-snapshot --volume-id ${vol_id} --description "root image for ${name}" | jq -r .SnapshotId )

while [ $( aws ec2 describe-snapshots --snapshot-ids ${snap_id} | jq -r .Snapshots[].State ) != "completed" ]; do
    echo "waiting for snapshot ${snap_id} to complete"
    sleep 5
done

## kernel-id hard-coded
## see http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/UserProvidedKernels.html
## fuck me, bash space escaping is a pain in the ass.
image_id=$( aws ec2 register-image --kernel-id aki-919dcaf8 --architecture x86_64 --name "${ami_name}" --root-device-name /dev/sda1 --block-device-mappings "[{\"DeviceName\":\"/dev/sda\",\"Ebs\":{\"SnapshotId\":\"${snap_id}\",\"VolumeSize\":10}},{\"DeviceName\":\"/dev/sdb\",\"VirtualName\":\"ephemeral0\"}]" | jq -r .ImageId )

echo "created AMI with id ${image_id}"
