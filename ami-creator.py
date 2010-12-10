#!/usr/bin/python -tt
#
# ami-creator: Create an EC2 AMI image
#
# Copyright 2010, Jeremy Katz
# Jeremy Katz <katzj@fedoraproject.org>
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

import logging
import optparse
import os
import sys

import imgcreate

class Usage(Exception):
    def __init__(self, msg = None):
        Exception.__init__(self, msg)

def parse_options(args):
    parser = optparse.OptionParser()

    # options related to the image
    imgopt = optparse.OptionGroup(parser, "Image options",
                                  "These options define the created image.")
    imgopt.add_option("-c", "--config", type="string", dest="kscfg",
                      help="Path or url to kickstart config file")
    imgopt.add_option("-n", "--name", type="string", dest="name",
                      help="Name to use for the image")
    parser.add_option_group(imgopt)

    # options related to the config of your system
    sysopt = optparse.OptionGroup(parser, "System directory options",
                                  "These options define directories used on your system for creating the live image")
    sysopt.add_option("-t", "--tmpdir", type="string",
                      dest="tmpdir", default="/var/tmp",
                      help="Temporary directory to use (default: /var/tmp)")
    sysopt.add_option("", "--cache", type="string",
                      dest="cachedir", default=None,
                      help="Cache directory to use (default: private cache")
    parser.add_option_group(sysopt)

    imgcreate.setup_logging(parser)

    # debug options not recommended for "production" images
    # Start a shell in the chroot for post-configuration.
    parser.add_option("-l", "--shell", action="store_true", dest="give_shell",
                      help=optparse.SUPPRESS_HELP)
    

    (options, args) = parser.parse_args()
    if not options.kscfg:
        raise Usage("Kickstart file must be provided")

    return options

class AmiCreator(imgcreate.LoopImageCreator):
    # FIXME: refactor into imgcreate.LoopImageCreator
    def _get_kernel_options(self):
        """Return a kernel options string for bootloader configuration."""
        r = imgcreate.kickstart.get_kernel_args(self.ks, default = "ro")
        return r

    def _get_fstab(self):
        s = "/dev/sda1  /    %s     defaults   0 0\n" %(self._fstype,)
        s += self._get_fstab_special()
        return s
    
    def _create_bootconfig(self):
        # FIXME: should we handle a different root dev?
        imgtemplate = """title %(title)s %(version)s
        root (hd0)
        kernel /boot/vmlinuz-%(version)s root=/dev/sda1 %(bootargs)s
        initrd /boot/initrd-%(version)s.img
"""

        cfg = """default=0
timeout=2

"""
        
        kernels = self._get_kernel_versions()
        versions = []
        for ktype in kernels:
            versions.extend(kernels[ktype])

        for version in versions:
            cfg += imgtemplate % {"title": self.name,
                                  "version": version,
                                  "bootargs": self._get_kernel_options()}

        grubcfg = open(self._instroot + "/boot/grub/grub.conf", "w")
        grubcfg.write(cfg)
        grubcfg.close()

        # ec2 (pvgrub) expects to see /boot/grub/menu.lst
        os.link(self._instroot + "/boot/grub/grub.conf",
                self._instroot + "/boot/grub/menu.lst")

def main():
    try:
        options = parse_options(sys.argv[1:])
    except Usage, msg:
        logging.error(msg)
        return 1

    if os.geteuid() != 0:
        logging.error("ami-creator must be run as root")
        return 1

    ks = imgcreate.read_kickstart(options.kscfg)
    name = imgcreate.build_name(options.kscfg)
    if options.name:
        name = options.name

    name = "ami"
    creator = AmiCreator(ks, name)
    creator.tmpdir = os.path.abspath(options.tmpdir)
    if options.cachedir:
        options.cachedir = os.path.abspath(options.cachedir)

    try:
        creator.mount(cachedir=options.cachedir)
        creator.install()
        creator.configure()
        if options.give_shell:
            print "Launching shell. Exit to continue."
            print "----------------------------------"
            creator.launch_shell()
        creator.unmount()
        creator.package()
    except imgcreate.CreatorError, e:
        logging.error("Error creating Live CD: %s" %(e,))
        return 1
    finally:
        creator.cleanup()

    return 0

if __name__ == "__main__":
    sys.exit(main())
