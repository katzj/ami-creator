#!/bin/bash

## deregisters an AMI and removes its associated block device snapshot.  Will
## likely fail if there are multiple EBS BlockDeviceMappings.

set -e
set -u

[ $# -eq 1 ] || { echo "usage: $0 <ami id>"; exit 1; }

image_id="${1}"

snap_id="$( aws ec2 describe-images --image-ids ${image_id} | jq -r '.Images[].BlockDeviceMappings[] | select(.Ebs).Ebs.SnapshotId' )"

echo "deregistering ${image_id}"
aws ec2 deregister-image --image-id ${image_id}

echo "deleting snapshot ${snap_id}"
aws ec2 delete-snapshot --snapshot-id ${snap_id}
