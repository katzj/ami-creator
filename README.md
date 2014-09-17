# ami-creator

A simple tool built on python-imgcreate to create CentOS AMIs for EC2 using
Kickstart configs.  Supports ebs- and instance-store-backed instances.

## howto

1. clone this repo on an EC2 instance
2. attach a 10G EBS volume, attach it so it appears at `/dev/xvdj`
3. create `/media/ephemeral0/build` and `/media/ephemeral0/cache` directories
4. create the base image from a kickstart config:

    sudo ./ami_creator/ami_creator.py -c ks-centos6.cfg -n my-image-name -t /media/ephemeral0/build --cache=/media/ephemeral0/cache

5. transfer the image to the attached EBS volume:

    sudo prepare-volume.sh

6. create and launch the instance:

    ./create-image.sh


## add'l resources

* [Announcing ami-creator](http://velohacker.com/2010/12/13/announcing-ami-creator/)
* [CentOS AMIs from Kickstart](http://dan.carley.co/blog/2012/04/17/centos-amis-from-kickstart/)
* [How to build your own S3- and EBS-backed instances](http://amazonaws.michael--martinez.com)
* [Using Your Own Linux Kernels - Amazon Elastic Compute Cloud](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/UserProvidedKernels.html)
* [How to make your own CentOS 6 AMIs](http://www.bashton.com/blog/2012/how-to-make-your-own-centos-6-amis/)
* [CentOS 5 kickstart options](http://www.centos.org/docs/5/html/Installation_Guide-en-US/s1-kickstart2-options.html)

## original `README`

    ami-creator

    A simple tool based on python-imgcreate to create Fedora/Red Hat style 
    images that can be used as an AMI in EC2.

    Takes a kickstart config like the rest of livecd-creator, etc and spits out a
    disk image file that's suitable to upload as an s3 ami.  To do the upload right
    now, you'll want to run something like
        ec2-bundle-image
        ec2-upload-bundle
        ec2-register
    after having created your base image file.  

    Tested with the following as guests:
      * CentOS 5.5
      * Fedora 14
    See the configs/ directory for example configs that work for each of these.


    Jeremy Katz <katzj@fedoraproject.org>
    2010 December 10

