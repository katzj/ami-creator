#!/bin/bash

set -e -u

basedir="$( cd $( dirname $0 )/.. && /bin/pwd -P )"
workdir="${basedir}/work"

if [ $# -ne 3 ]; then
    echo "usage: $0 <host_distro> <kickstart_cfg> <name>"
    exit 1
fi

host_distro="$1"
kickstart_cfg="$2"
name="$3"

docker_file="${basedir}/utils/Dockerfile.${host_distro}"
docker_image="ami_creator/${host_distro}"

if [ ! -e "${docker_file}" ]; then
    echo "unsupported host distro: ${host_distro}"
    exit 1
fi

if [ ! -e "${kickstart_cfg}" ]; then
    echo "${kickstart_cfg} does not exist"
    exit 1
fi

kickstart_base="$( basename ${kickstart_cfg} )"
kickstart_root="$( cd $( dirname ${kickstart_cfg} ) && /bin/pwd -P )"

mkdir -p ${workdir}/{build,cache}

## build the image if it doesn't already exist
docker inspect ${docker_image} >/dev/null 2>&1 || \
    docker build -t ${docker_image} - < ${docker_file}

docker run \
    -i -t \
    --rm \
    --privileged \
    --volume=${basedir}:/srv/ami-creator:ro \
    --volume=${kickstart_root}:/srv/image-config:ro \
    --volume=${workdir}:/srv/work \
    ${docker_image} \
    \
    /bin/bash -c " \
        /srv/ami-creator/ami_creator/ami_creator.py \
            -d -v \
            -c /srv/image-config/${kickstart_base} \
            -n ${name} \
            -t /tmp \
            --cache=/srv/work/cache \
        && mv ${name}.img /srv/work/build/
    "
