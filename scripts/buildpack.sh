#!/usr/bin/env bash
#
# Copyright (C) 2017 Alexey Kopytov <akopytov@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

# Build packages for a specified architecture and upload them packagecloud.io
# Expects the following environment variables to be defined:
#
#   ARCH - architecture. 'aarch64', 'x86_64 and 'i386' are currently supported
#          values. If not set, the script behaves as if it was sequentially
#          called with 'x86_64' and 'i386' values
#
#   PACKAGECLOUD_TOKEN - packagecloud.io API token
#
#   PACKAGECLOUD_USER - packagecloud.io user name, defaults to 'akopytov'
#
#   PACKAGECLOUD_REPO - packagecloud.io repository. The default is 'sysbench'
#                       for releases (i.e. if git HEAD corresponds to a tag),
#                       and 'sysbench-prereleases' otherwise.
#
#   PACKPACK_REPO - packpack repository to use. Defaults to packpack/packpack.

set -eu

PACKAGECLOUD_USER=${PACKAGECLOUD_USER:-"akopytov"}
PACKPACK_REPO=${PACKPACK_REPO:-packpack/packpack}

distros_x86_64=(
    "el 6 x86_64"
    "el 7 x86_64"
    "fedora 24 x86_64"
    "fedora 25 x86_64"
    "ubuntu precise x86_64"
    "ubuntu trusty x86_64"
    "ubuntu xenial x86_64"
    "ubuntu yakkety x86_64"
    "debian wheezy x86_64"
    "debian jessie x86_64"
)

distros_i386=(
    "ubuntu precise i386"
    "ubuntu trusty i386"
    "ubuntu xenial i386"
    "ubuntu yakkety i386"
    "debian wheezy i386"
    "debian jessie i386"
)

distros_aarch64=(
    "el 7 aarch64"
    "fedora 24 aarch64"
    "fedora 25 aarch64"
    "ubuntu precise aarch64"
    "ubuntu trusty aarch64"
    "ubuntu xenial aarch64"
    "ubuntu yakkety aarch64"
    "debian jessie aarch64"
)

main()
{
    if [ ! -r configure.ac ]; then
        echo "This script should be executed from the source root directory."
        exit 1
    fi

    if [ -z "${PACKAGECLOUD_TOKEN+x}" ]; then
        echo "This script expects PACKAGECLOUD_TOKEN to be defined."
        exit 1
    fi

    if [ ! which package_cloud >/dev/null 2>&1 ]; then
        echo "This script requires package_cloud. You can install it by running:"
        echo "  gem install package_cloud"
    fi

    if [ ! -d packpack ]; then
        git clone https://github.com/${PACKPACK_REPO} packpack
    fi

    if [ -z "${PACKAGECLOUD_REPO+x}" ]; then
        # Upload builds corresponding to release tags to the 'sysbench'
        # repository, push other ones to 'sysbench-prereleases'
        if ! git describe --long --always >/dev/null 2>&1 ; then
            echo "Either run this script from a git repository, or specify "
            echo "the packagecloud repository explicitly with PACKAGECLOUD_REPO"
            exit 1
        fi
        local commits=$(git describe --long --always |
                            sed -n 's/^\([0-9\.]*\)-\([0-9]*\)-\([a-z0-9]*\)/\2/p')
        if [ ${commits:-0} = 0 ]; then
            export PACKAGECLOUD_REPO=sysbench
        else
            export PACKAGECLOUD_REPO=sysbench-prereleases
        fi
    fi

    declare -a distros

    if [ -z "${ARCH+x}" ]; then
        distros=("${distros_x86_64[@]}" "${distros_i386[@]}")
    else
        case "$ARCH" in
            x86_64)
                distros=( "${distros_x86_64[@]}" )
                ;;
            i386)
                distros=( "${distros_i386[@]}" )
                ;;
            aarch64)
                distros=( "${distros_aarch64[@]}" )
                ;;
            *)
                echo "Invalid ARCH value: $ARCH"
                exit 1
                ;;
        esac
    fi

    export PRODUCT=sysbench

    for d in "${distros[@]}"; do
        echo "*** Building package for $d ***"
        local t=( $d )
        export OS=${t[0]}
        export DIST=${t[1]}
        export ARCH=${t[2]}

        # Replace "el" with "centos" for packpack, as there is no "el-*" docker
        # images for some architectures
        local PPOS=${OS/#el/centos}
        OS="$PPOS" packpack/packpack

        # To avoid name conflicts, deploy source packages only for
        # "default", i.e. x86_64 architecture
        if [ "${ARCH}" = "x86_64" ]; then
            files="$(ls build/*.{rpm,deb,dsc} 2>/dev/null || :)"
        else
            files="$(ls build/*{[^c].rpm,.deb} 2>/dev/null || :)"
        fi

        if [ -z "$files" ]; then
            echo "No package files to push"
            exit 1
        fi

        echo "Pushing packages to ${PACKAGECLOUD_USER}/${PACKAGECLOUD_REPO}"

        package_cloud push \
                      ${PACKAGECLOUD_USER}/${PACKAGECLOUD_REPO}/${OS}/${DIST} \
                      $files

        packpack/packpack clean
    done
}

main
