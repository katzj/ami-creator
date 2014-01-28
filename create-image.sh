#!/bin/bash

set -x
set -e
set -u

snap_id=$( aws ec2 create-snapshot --volume-id vol-9c03c3ee | jq -r .SnapshotId )

while [ $( aws ec2 describe-snapshots --snapshot-ids ${snap_id} | jq -r .Snapshots[].State ) != "completed" ]; do
    sleep 5
done

image_id=$( aws ec2 register-image \
    --kernel-id aki-919dcaf8 \
    --name ami-creator-001 \
    --architecture x86_64 \
    --root-device-name /dev/sda1 \
    --block-device-mappings "[{
        \"DeviceName\": \"/dev/sda\",
        \"Ebs\": {
            \"SnapshotId\": \"${snap_id}\",
            \"VolumeSize\": 10
        }
    },
    {
        \"DeviceName\": \"/dev/sdb\",
        \"VirtualName\": \"ephemeral0\"
    }]" | jq -r .ImageId )

instance_id=$( aws ec2 run-instances --image-id $image_id --instance-type t1.micro --key-name knife | jq -r .Instances[].InstanceId )

while [ $( aws ec2 describe-instances --instance-ids $instance_id | jq -r .Reservations[].Instances[].State.Name ) != "running" ]; do
    sleep 5
done

echo "snap_id=${snap_id}; image_id=${image_id}; instance_id=${instance_id};"

# aws ec2 get-console-output --instance-id ${instance_id} | jq -r .Output

# aws ec2 terminate-instances --instance-ids ${instance_id}
# aws ec2 deregister-image --image-id ${image_id}
# aws ec2 delete-snapshot --snapshot-id ${snap_id}

