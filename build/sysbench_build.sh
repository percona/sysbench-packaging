#!/bin/sh

shell_quote_string() {
  echo "$1" | sed -e 's,\([^a-zA-Z0-9/_.=-]\),\\\1,g'
}

usage () {
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --builddir=DIR      Absolute path to the dir where all actions will be performed
        --get_sources       Source will be downloaded from github
        --build_src_rpm     If it is 1 src rpm will be built
        --build_source_deb  If it is 1 source deb package will be built
        --build_rpm         If it is 1 rpm will be built
        --build_deb         If it is 1 deb will be built
        --install_deps      Install build dependencies(root previlages are required)
        --branch            Branch from which submodules should be taken(default master)
        --help) usage ;;
Example $0 --builddir=/tmp/SYSBENCH --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
        exit 1
}

append_arg_to_args () {
  args="$args "`shell_quote_string "$1"`
}

parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV
    then
        pick_args=1
        shift
    fi
  
    for arg do
        val=`echo "$arg" | sed -e 's;^--[^=]*=;;'`
        optname=`echo "$arg" | sed -e 's/^\(--[^=]*\)=.*$/\1/'`
        case "$arg" in
            # these get passed explicitly to mysqld
            --builddir=*) WORKDIR="$val" ;;
            --build_src_rpm=*) SRPM="$val" ;;
            --build_source_deb=*) SDEB="$val" ;;
            --build_rpm=*) RPM="$val" ;;
            --build_deb=*) DEB="$val" ;;
            --get_sources=*) SOURCE="$val" ;;
            --branch=*) SYSBENCH_BRANCH="$val" ;;
            --tpcc_branch=*) TPC_BRANCH="$val" ;;
            --pack_branch=*) PACK_BRANCH="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
            --help) usage ;;      
            *)
              if test -n "$pick_args"
              then
                  append_arg_to_args "$arg"
              fi
              ;;
        esac
    done
}

check_workdir(){
    if [ "x$WORKDIR" = "x$CURDIR" ]
    then
        echo >&2 "Current directory cannot be used for building!"
        exit 1
    else
        if ! test -d "$WORKDIR"
        then
            echo >&2 "$WORKDIR is not a directory."
            exit 1
        fi
    fi
    return
}

add_percona_yum_repo(){
    if [ ! -f /etc/yum.repos.d/percona-dev.repo ]
    then
        cat >/etc/yum.repos.d/percona-dev.repo <<EOL
[percona-dev-$basearch]
name=Percona internal YUM repository for build slaves \$releasever - \$basearch
baseurl=http://jenkins.percona.com/yum-repo/\$releasever/RPMS/\$basearch
gpgkey=http://jenkins.percona.com/yum-repo/PERCONA-PACKAGING-KEY
gpgcheck=0
enabled=1

[percona-dev-noarch]
name=Percona internal YUM repository for build slaves \$releasever - noarch
baseurl=http://jenkins.percona.com/yum-repo/\$releasever/RPMS/noarch
gpgkey=http://jenkins.percona.com/yum-repo/PERCONA-PACKAGING-KEY
gpgcheck=0
enabled=1
EOL
    fi
    return
}

add_percona_apt_repo(){
    if [ ! -f /etc/apt/sources.list.d/percona-dev.list ]
    then
        cat >/etc/apt/sources.list.d/percona-dev.list <<EOL
deb http://jenkins.percona.com/apt-repo/ @@DIST@@ main
deb-src http://jenkins.percona.com/apt-repo/ @@DIST@@ main
EOL
    sed -i "s:@@DIST@@:$OS_NAME:g" /etc/apt/sources.list.d/percona-dev.list
    fi
    return
}

get_sources(){
    cd $WORKDIR
    if [ $SOURCE = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi
    git clone ${GIT_REPO}
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi
    mv $NAME $NAME-$VERSION
    cd $NAME-$VERSION
    if [ ! -z $SYSBENCH_BRANCH ]
    then
        git reset --hard
        git clean -xdf
        git checkout $BRANCH
    fi

    rm -f ${WORKDIR}/*.tar.gz
    #
    REVISION=$(git rev-parse --short HEAD)
    #
    git clone $TPCC_REPO tpcc
        cd tpcc
            git fetch origin
            if [ ! -z ${TPCC_BRANCH} ]; then
                git reset --hard
                git clean -xdf
                git checkout ${TPCC_BRANCH}
            fi
    
    cd ${WORKDIR}

    echo "VERSION=${VERSION}" > sysbench.properties
    echo "REVISION=${REVISION}" >> sysbench.properties
    echo "RPM_RELEASE=${RPM_RELEASE}" >> sysbench.properties
    echo "DEB_RELEASE=${DEB_RELEASE}" >> sysbench.properties
    echo "GIT_REPO=${GIT_REPO}" >> sysbench.properties
    BRANCH_NAME="${BRANCH}"
    echo "BRANCH_NAME=${BRANCH_NAME}" >> sysbench.properties
    PRODUCT=sysbench
    echo "PRODUCT=${PRODUCT}" >> sysbench.properties
    PRODUCT_FULL=${PRODUCT}-${VERSION}
    echo "PRODUCT_FULL=${PRODUCT_FULL}" >> sysbench.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >> sysbench.properties
    echo "BUILD_ID=${BUILD_ID}" >> sysbench.properties
    #
    if [ -z "${DESTINATION}" ]; then
      export DESTINATION=experimental
    fi 
    #
    echo "DESTINATION=${DESTINATION}" >> sysbench.properties
    echo "UPLOAD=UPLOAD/builds/${PRODUCT}/${PRODUCT_FULL}/${BRANCH_NAME}/${REVISION}/${BUILD_ID}" >> sysbench.properties
    #
    tar -zcvf ${NAME}-${VERSION}.tar.gz ${NAME}-${VERSION} --exclude=.bzr* --exclude=.git*
    
    
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PRODUCT}-${VERSION}.tar.gz $WORKDIR/source_tarball
    cp ${PRODUCT}-${VERSION}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    rm -rf $NAME
    return
}

get_system(){
    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        OS_NAME="el$RHEL"
        OS="rpm"
    else
        ARCH=$(uname -m)
        OS_NAME="$(lsb_release -sc)"
        OS="deb"
    fi
    return
}

install_deps() {
    if [ $INSTALL = 0 ]
    then
        echo "Dependencies will not be installed"
        return;
    fi
    if [ ! $( id -u ) -eq 0 ]
    then
        echo "It is not possible to instal dependencies. Please run as root"
        exit 1
    fi
    CURPLACE=$(pwd)
    if [ "x$OS" = "xrpm" ]
    then
        if [ $RHEL -lt 9 ]; then
            add_percona_yum_repo
        else
            yum -y update
            yum-config-manager --enable ol9_codeready_builder
        fi
        yum -y install git wget
        yum -y install epel-release rpmdevtools bison yum-utils
        yum -y install rpm-build automake libaio-devel libtool make postgresql-devel mariadb-devel
        if [ $RHEL = 8 ]; then
            cat /etc/os-release
            sed -i 's/mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/CentOS-*
            sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
            yum -y update
            sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
            sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
        fi
        if [ $RHEL = 9 ]; then
            cat /etc/os-release
            yum -y update
            yum -y install python3 gnutls-devel libtool || true
            ln -s /usr/bin/python3.9 /usr/bin/python || true
        fi
        if [ $RHEL -lt 9 ]; then
            wget -O /etc/yum.repos.d/percona-dev.repo http://jenkins.percona.com/yum-repo/percona-dev.repo
        fi
        yum -y install automake bzip2 cmake make gcc-c++ gcc git openssl openssl-devel gnutls gnutls-devel libtool patch
        yum -y install python3 perl-IPC-Cmd libuuid-devel
        if [ $RHEL -eq 8 ]; then
            rpm -q centos-release || true
            rpm -q centos-linux-release || true
            yum -y install epel-release
            yum -y install libcurl-devel libunwind libunwind-devel
        fi
        if [ $RHEL -lt 8 ]; then
            yum -y install libunwind libunwind-devel
            yum -y upgrade
        fi
        if [ $RHEL -eq 7 ]; then
            /usr/bin/python -V
            head -1 /usr/bin/yum
        fi

        cd $WORKDIR
        link="https://raw.githubusercontent.com/akopytov/sysbench/${BRANCH}/rpm/sysbench.spec"
        wget $link
        sed -i 's|x.y.z|1.0|' sysbench.spec
        yum-builddep -y $WORKDIR/$NAME.spec
    else
        apt-get -y update
        DEBIAN_FRONTEND=noninteractive apt-get -y install git wget curl lsb-release gnupg2 apt-utils
      #  add_percona_apt_repo
        apt-get -y update
        DEBIAN_FRONTEND=noninteractive apt-get -y install fakeroot debhelper debconf devscripts equivs libpq-dev pkg-config
        CURPLACE=$(pwd)
        cd $WORKDIR
        link="https://raw.githubusercontent.com/akopytov/sysbench/master/debian/control"
        wget $link
        cd $CURPLACE
        sed -i 's:apt-get :apt-get -y --force-yes :g' /usr/bin/mk-build-deps
        mk-build-deps --install $WORKDIR/control
        sed -e '/.*backports.*/d' /etc/apt/sources.list > sources.list.new
        mv -f sources.list.new /etc/apt/sources.list

        export DEBIAN_VERSION="$(lsb_release -sc)"
        if [ $DEBIAN_VERSION = focal ]; then
           DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
        fi
        if [[ ${DEBIAN_VERSION} = buster ]]; then
            wget http://ftp.de.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2021.1.1_all.deb
            apt -y install ./debian-archive-keyring_2021.1.1_all.deb
            DEBIAN_FRONTEND=noninteractive  apt-get -y update --allow-releaseinfo-change || true
        fi
        DEBIAN_FRONTEND=noninteractive apt-get update || true
        apt-get -y install wget gnupg2 curl
        wget --no-check-certificate https://jenkins.percona.com/apt-repo/8507EFA5.pub -O - | sudo apt-key add -
        apt-get -y install dpkg-dev
        if [ $DEBIAN_VERSION = focal -o $DEBIAN_VERSION = jammy ]; then
            DEBIAN_FRONTEND=noninteractive apt-get -y install libaio-dev autoconf automake libtool default-libmysqlclient-dev libpq-dev pkg-config python2 build-essential devscripts debconf gcc g++
        else
            apt-get -y install dpkg-dev libaio-dev debhelper autoconf automake libtool libssl-dev libpq-dev pkg-config python build-essential devscripts debconf gcc g++
        fi
        apt-get -y install default-libmysqlclient-dev || true
    fi
    return;
}

get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'sysbench*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'sysbench*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]
        then
            echo "There is no $TARBALL for build"
            exit 1
        else
            cp $CURDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
        fi
    else
        cp $WORKDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
    fi
    return
}

get_deb_sources(){
    param=$1
    echo $param
    FILE=$(basename $(find $WORKDIR/source_deb -name "sysbench*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "sysbench*.$param" | sort | tail -n1))
        if [ -z $FILE ]
        then
            echo "There is no sources for build"
            exit 1
        else
            cp $CURDIR/source_deb/$FILE $WORKDIR/
        fi
    else
        cp $WORKDIR/source_deb/$FILE $WORKDIR/
    fi
    return
}

build_srpm(){
    if [ $SRPM = 0 ]
    then
        echo "SRC RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build src rpm here"
        exit 1
    fi
    cd $WORKDIR
    get_tar "source_tarball"
    #
    rm -fr rpmbuild
    TARFILE=$(basename $(find . -name 'sysbench-*.tar.gz' | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1}')
    VERSION_TMP=$(echo ${TARFILE}| awk -F '-' '{print $2}')
    VERSION=${VERSION_TMP%.tar.gz}
    #
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    #
    #bzr branch lp:~percona-core/sysbench/sysbench-packaging
    rm -rf sysbench-packaging
    git clone ${GIT_PACK_REPO}
    cd sysbench-packaging
    git checkout ${PACK_BRANCH}
    cd ..
    #
    cd ${WORKDIR}/rpmbuild/SPECS
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/rpm/sysbench.spec' --strip=2
    patch -p0 sysbench.spec < ${WORKDIR}/sysbench-packaging/rpm/spec.patch
    #
    cd ${WORKDIR}
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
    #
    sed -i "s:@@VERSION@@:${SYSBENCH_BRANCH}:g" rpmbuild/SPECS/sysbench.spec
    sed -i "s:@@RELEASE@@:${RPM_RELEASE}:g" rpmbuild/SPECS/sysbench.spec
    #
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .generic" rpmbuild/SPECS/sysbench.spec
    #

    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    #

}

build_rpm(){
    if [ $RPM = 0 ]
    then
        echo "RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build rpm here"
        exit 1
    fi
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'sysbench*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'sysbench*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
        else
            cp $CURDIR/srpm/$SRC_RPM $WORKDIR
        fi
    else
        cp $WORKDIR/srpm/$SRC_RPM $WORKDIR
    fi
    cd $WORKDIR
    SRCRPM=$(basename $(find . -name '*.src.rpm' | sort | tail -n1))
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    mv *.src.rpm rpmbuild/SRPMS
    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .el${RHEL}" --rebuild rpmbuild/SRPMS/${SRCRPM}
    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm
    
}

build_source_deb(){
    if [ $SDEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    rm -rf sysbench*
    get_tar "source_tarball"
    #
    TARFILE=$(basename $(find . -name 'sysbench-*.tar.gz' | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1}')
    VERSION_TMP=$(echo ${TARFILE}| awk -F '-' '{print $2}')
    VERSION=${VERSION_TMP%.tar.gz}
    #
    rm -fr ${NAME}-${VERSION}
    #
    NEWTAR=${NAME}_${VERSION}.orig.tar.gz
    mv ${TARFILE} ${NEWTAR}
    #
    #bzr branch lp:~percona-core/sysbench/sysbench-packaging
    rm -rf sysbench-packaging
    git clone ${GIT_PACK_REPO}
    cd sysbench-packaging
    git checkout ${PACK_BRANCH}
    cd ..
    #
    tar xzf ${NEWTAR}
    cd ${NAME}-${VERSION}
    patch -p0 < ${WORKDIR}/sysbench-packaging/debian/debian.patch
    dch -D unstable --force-distribution -v "${VERSION}-${DEB_RELEASE}" "Update to new upstream release SysBench ${VERSION}-${DEB_RELEASE}"
    dpkg-buildpackage -S
    #
    cd ../
    ls
    mkdir -p $WORKDIR/source_deb
    mkdir -p $CURDIR/source_deb
    cp *_source.changes $WORKDIR/source_deb
    cp *.dsc $WORKDIR/source_deb
    cp *.tar* $WORKDIR/source_deb
    cp *_source.changes $CURDIR/source_deb
    cp *.dsc $CURDIR/source_deb
    cp *.tar* $CURDIR/source_deb
}

build_deb(){
    if [ $DEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    for file in 'dsc' 'orig.tar.gz' 'changes' 'debian.tar.*z'
    do
        get_deb_sources $file
    done
    cd $WORKDIR
    rm -fv *.deb
    export DEBIAN_VERSION="$(lsb_release -sc)"
    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n 1))
    DIRNAME=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $1"-"$2}')
    VERSION=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $2}')
    ARCH=$(uname -m)
    #
    echo "ARCH=${ARCH}" >> sysbench.properties
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}" >> sysbench.properties
    echo VERSION=${VERSION} >> sysbench.properties
    #
    dpkg-source -x ${DSC}
    cd ${DIRNAME}
    #
    #if [ ${DEBIAN_VERSION} = "xenial" ]; then
    #    sed -ie 's/MYSQL_LIBS="-L$ac_cv_mysql_libs -lmysqlclient_r"/MYSQL_LIBS="-L$ac_cv_mysql_libs -lmysqlclient"/' m4/ac_check_mysqlr.m4
    #fi
    
    if [ ${DEBIAN_VERSION} = "stretch" ]; then
        sed -ie 's/libmysqlclient-dev/default-libmysqlclient-dev/' debian/control
    fi
    if [ ${DEBIAN_VERSION} = "focal" -o ${DEBIAN_VERSION} = "jammy" ]; then
        sed -ie 's/python/python2/' debian/control
    fi

    dch -b -m -D "$DEBIAN_VERSION" --force-distribution -v "${VERSION}-${DEB_RELEASE}.${DEBIAN_VERSION}" 'Update distribution'
    #
    dpkg-buildpackage -rfakeroot -uc -us -b
    mkdir -p $CURDIR/deb
    mkdir -p $WORKDIR/deb
    cp $WORKDIR/*.deb $WORKDIR/deb
    cp $WORKDIR/*.deb $CURDIR/deb
}

#main

CURDIR=$(pwd)
VERSION_FILE=$CURDIR/sysbench.properties
args=
WORKDIR=
SRPM=0
SDEB=0
RPM=0
DEB=0
SOURCE=0
TARBALL=0
OS_NAME=
ARCH=
OS=
SYSBENCH_BRANCH="1.0.20"
TPC_BRANCH="master"
BRANCH="1.0.20"
PACK_BRANCH="main"
INSTALL=0
RPM_RELEASE=6
DEB_RELEASE=6
REVISION=0
TPCC_REPO="https://github.com/Percona-Lab/sysbench-tpcc.git"
GIT_PACK_REPO="https://github.com/percona/sysbench-packaging.git"
GIT_REPO="https://github.com/akopytov/sysbench.git"
NAME=sysbench
parse_arguments PICK-ARGS-FROM-ARGV "$@"
VERSION=$SYSBENCH_BRANCH

check_workdir
get_system
install_deps
get_sources
build_srpm
build_source_deb
build_rpm
build_deb
