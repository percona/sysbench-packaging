Summary:       System performance benchmark
Name:          sysbench
Version:       @@VERSION@@
Release:       @@RELEASE@@%{?dist}
License:       GPLv2+
Group:         Applications/System
Source0:       %{name}-%{version}.tar.gz
URL:           https://launchpad.net/sysbench/
BuildRoot:     %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires: mysql-devel
BuildRequires: libaio-devel
BuildRequires: automake
BuildRequires: libtool

%description
SysBench is a modular, cross-platform and multi-threaded benchmark
tool for evaluating OS parameters that are important for a system
running a database under intensive load.

The idea of this benchmark suite is to quickly get an impression about
system performance without setting up complex database benchmarks or
even without installing a database at all. Current features allow to
test the following system parameters:
- file I/O performance
- scheduler performance
- memory allocation and transfer speed
- POSIX threads implementation performance
- database server performance (OLTP benchmark)

Primarily written for MySQL server benchmarking, SysBench will be
further extended to support multiple database backends, distributed
benchmarks and third-party plug-in modules.

%prep
%setup -q

%build
touch NEWS AUTHORS
autoreconf -vif
#%configure --with-mysql

make

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT
rm -f $RPM_BUILD_ROOT%{_docdir}/sysbench/manual.html

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc ChangeLog COPYING  README.md
%dir %{_docdir}
%dir %{_datadir}/sysbench
%{_datadir}/sysbench/*
%{_bindir}/*


%changelog
* Fri Feb 17 2017 Alexey Bychko <alexey.bychko@percona.com> 1.0.1-1
- Build new version 1.0.1

* Wed Nov 19 2014 Tomislav Plavcic <tomislav.plavcic@percona.com> 0.5-6
- Build from lp code rev 128

* Wed Oct 22 2014 Tomislav Plavcic <tomislav.plavcic@percona.com> 0.5-5
- Build from lp code rev 126

* Thu Oct 10 2013 Frederic Descamps <lefred@percona.com> 0.5-4
- Build from lp code rev 119

* Fri Sep 07 2012 Frederic Descamps <lefred@percona.com> 0.5-3
- New build from updated trunk

* Wed Jun 13 2012 Frederic Descamps <lefred@percona.com> 0.5-2
- Add the tests

* Wed Jun 13 2012 Frederic Descamps <lefred@percona.com> 0.5-1
- New package from last lp code rev 107

* Tue Sep 06 2011 Xavier Bachelot <xavier@bachelot.org> 0.4.12-5
- Add BR: libaio-devel (rhbz#735882).

* Wed Mar 23 2011 Dan Horák <dan@danny.cz> - 0.4.12-4
- rebuilt for mysql 5.5.10 (soname bump in libmysqlclient)

* Wed Feb 09 2011 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.4.12-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_15_Mass_Rebuild

* Fri Dec 24 2010 Xavier Bachelot <xavier@bachelot.org> 0.4.12-2
- Rebuild against new mysql.

* Wed Jul 07 2010 Xavier Bachelot <xavier@bachelot.org> 0.4.12-1
- Update to 0.4.12.

* Fri Aug 21 2009 Tomas Mraz <tmraz@redhat.com> - 0.4.10-5
- rebuilt with new openssl

* Sun Jul 26 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.4.10-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Wed Mar 18 2009 Xavier Bachelot <xavier@bachelot.org> 0.4.10-3
- License is GPLv2+, not GPLv2.

* Sat Mar 14 2009 Xavier Bachelot <xavier@bachelot.org> 0.4.10-2
- Make postgres support optional, the version in rhel4 is too old.
- Drop TODO and manual.html from %%doc, they are empty.

* Thu Mar 05 2009 Xavier Bachelot <xavier@bachelot.org> 0.4.10-1
- Adapt original spec file taken from PLD.
