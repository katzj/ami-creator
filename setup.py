#!/usr/bin/env python
#
# setup.py -- Installation for ami-creator
#
# Copyright 2010, Jeremy Katz
# Jeremy Katz <katzj@fedoraproject.org>
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

from ez_setup import use_setuptools
use_setuptools()

from setuptools import setup, find_packages

PACKAGE_NAME = 'ami-creator'

setup(name=PACKAGE_NAME,
      version="0.3",
      license="GPL",
      description="Command line tools for creating AMIs from kickstart files.",
      entry_points = {
          'console_scripts': [
              'ami-creator = ami_creator.ami_creator:main',
          ],
      },
      packages=find_packages(),
      include_package_data=True,
      maintainer="Jeremy Katz",
      maintainer_email="katzj@fedoraproject.com",
      url="https://github.com/katzj/ami-creator/"
)
