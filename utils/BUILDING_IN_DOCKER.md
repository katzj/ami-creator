Since `ami_creator` uses the yum on the host system to build an image, you can
run into problems if the host and target distributions don't agree.  For
example, CentOS 7 packages use xz compression, but that's not available to yum
on CentOS 6.  And it seems plausible that building a CentOS 6 image on CentOS 7
would result in an RPM database that can't be read by a live CentOS 6 instance.

Fortunately, we have Docker.

## `build_in_docker.sh`

Usage:

    build_in_docker.sh <host distro> <kickstart config> <name>

`host distro` is matched against the corresponding `Dockerfile.?` in this
directory.  `../work/build/<name>.img` is created, which can then be used for an
S3-backed AMI, or written to an EBS volume to be snapshotted and registered as
an EBS-backed AMI.

## CentOS 6

Build CentOS 6 images using a CentOS 6 host environment.

    ./build_in_docker.sh centos6 /path/to/centos6.ks centos6

## CentOS 7

Build CentOS 7 images using a _Fedora 20_ host environment.  CentOS 7 doesn't
have the required `python-imgcreate` package available, either in the base
repository or in EPEL.

    ./build_in_docker.sh fedora20 /path/to/centos7.ks centos7
