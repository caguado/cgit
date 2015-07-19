# Review bug: https://bugzilla.redhat.com/479723

%global gitver      2.3.2
%global cachedir    %{_localstatedir}/cache/%{name}
%global filterdir   %{_libexecdir}/%{name}/filters
%global scriptdir   %{_localstatedir}/www/cgi-bin
%global cgitdata    %{_datadir}/%{name}

%global make_cgit \
export CFLAGS="%{optflags}" \
export LDFLAGS="%{?__global_ldflags}" \
make V=1 %{?_smp_mflags} \\\
     DESTDIR=%{buildroot} \\\
     INSTALL="install -p"  \\\
     CACHE_ROOT=%{cachedir} \\\
     CGIT_SCRIPT_PATH=%{scriptdir} \\\
     CGIT_SCRIPT_NAME=cgit \\\
     CGIT_DATA_PATH=%{cgitdata} \\\
     docdir=%{docdir} \\\
     filterdir=%{filterdir} \\\
     prefix=%{_prefix}

Name:           cgit
Version:        0.11.2.2bbp
Release:        1%{?dist}
Summary:        A fast web interface for git

Group:          Development/Tools
License:        GPLv2
URL:            http://git.zx2c4.com/cgit/
Source0:        http://git.zx2c4.com/cgit/snapshot/%{name}-%{version}.tar.bz2
Source1:        https://www.kernel.org/pub/software/scm/git/git-%{gitver}.tar.gz
Source2:        cgitrc
Source3:        gerrit-auth.lua
BuildRoot:      %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires:  asciidoc
%if 0%{?rhel} && 0%{?rhel} <= 5
# These are missing asciidoc requirements
BuildRequires:  docbook-style-xsl libxslt
%endif
%if 0%{?fedora} || 0%{?rhel} >= 6
BuildRequires:  libcurl-devel
%else
BuildRequires:  curl-devel
%endif
BuildRequires:  openssl-devel
BuildRequires:  lua-devel
Requires:       httpd

%description
Cgit is a fast web interface for git.  It uses caching to increase performance.

%prep
%setup -q -a 1

# setup the git dir
rm -rf git
mv git-%{gitver} git
sed -i 's/^\(CFLAGS = \).*/\1%{optflags}/' git/Makefile

%build
%{make_cgit}

# Something in the a2x chain doesn't like running in parallel. :/
%{make_cgit} -j1 doc-man doc-html


%install
rm -rf %{buildroot}
%{make_cgit} install install-man
install -d -m0755 %{buildroot}%{_sysconfdir}
install -p -m0644 %{SOURCE2} %{buildroot}%{_sysconfdir}/cgitrc
install -p -m0644 %{SOURCE3} %{buildroot}%{_libexecdir}/cgit/filters/gerrit-auth.lua
install -d -m0755 %{buildroot}%{cachedir}


%clean
rm -rf %{buildroot}


%files
%defattr(-,root,root,-)
%doc COPYING README* *.html
%config(noreplace) %{_sysconfdir}/cgitrc
%dir %attr(-,apache,root) %{cachedir}
%{cgitdata}
%{filterdir}
%{scriptdir}/*
%{_mandir}/man*/*


%changelog
* Thu Jul 09 2015 Carlos Aguado <carlos.aguado@epfl.ch> 0.11.2.1bbp-1
- Update to upstream v0.11.2
- Add authentication and authorization checks

* Sun May 18 2014 Carlos Aguado <carlos.aguado@epfl.ch> 0.10.1.1bbp-1
- Update to 0.10.1.1bbp
- Remove cgit.httpd
- Remove patches integrated in the repository (highlight)

* Thu Feb 27 2014 Kevin Fenzi <kevin@scrye.com> 0.10.1-1
- Update to 0.10.1
- Correctly enable lua filters. 

* Wed Feb 19 2014 Kevin Fenzi <kevin@scrye.com> 0.10-1
- Update to 0.10

* Sat Aug 03 2013 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.9.2-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_20_Mass_Rebuild

* Mon May 27 2013 Todd Zullinger <tmz@pobox.com> - 0.9.2-1
- Update to 0.9.2, fixes CVE-2013-2117

* Wed Feb 13 2013 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.9.1-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_19_Mass_Rebuild

* Wed Nov 21 2012 Kevin Fenzi <kevin@scrye.com> 0.9.1-3
- Fixed ldflags. Fixes bug 878611

* Sat Nov 17 2012 Kevin Fenzi <kevin@scrye.com> 0.9.1-2
- Add patch to use correct version of highlight for all branches except epel5

* Thu Nov 15 2012 Kevin Fenzi <kevin@scrye.com> 0.9.1-1
- Update to 0.9.1
- Fixes bug #870714 - CVE-2012-4548
- Fixes bug #820733 - CVE-2012-4465

* Wed Jul 18 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.9.0.2-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_18_Mass_Rebuild

* Thu Jan 12 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.9.0.2-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_17_Mass_Rebuild

* Fri Jul 22 2011 Todd Zullinger <tmz@pobox.com> - 0.9.0.2-2
- Fix potential XSS vulnerability in rename hint

* Thu Jul 21 2011 Todd Zullinger <tmz@pobox.com> - 0.9.0.2-1
- Update to 0.9.0.2

* Sun Mar 06 2011 Todd Zullinger <tmz@pobox.com> - 0.9-1
- Update to 0.9
- Fixes: CVE-2011-1027
  http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2011-1027
- Generate and install man page and html docs
- Use libcurl-devel on RHEL >= 6
- Include example filter scripts
- Update example cgitrc

* Tue Feb 08 2011 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.8.2.1-5
- Rebuilt for https://fedoraproject.org/wiki/Fedora_15_Mass_Rebuild

* Mon Sep 27 2010 Todd Zullinger <tmz@pobox.com> - 0.8.2.1-4
- Appy upstream git patch for CVE-2010-2542 (#618108)

* Fri Aug 21 2009 Tomas Mraz <tmraz@redhat.com> - 0.8.2.1-3
- rebuilt with new openssl

* Fri Jul 24 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.8.2.1-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Sun Mar 15 2009 Todd Zullinger <tmz@pobox.com> - 0.8.2.1-1
- Update to 0.8.2.1

* Mon Feb 23 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 0.8.2-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_11_Mass_Rebuild

* Sun Feb 01 2009 Todd Zullinger <tmz@pobox.com> - 0.8.2-1
- Update to 0.8.2
- Drop upstreamed Makefile patch

* Sun Jan 18 2009 Todd Zullinger <tmz@pobox.com> - 0.8.1-2
- Rebuild with new openssl

* Mon Jan 12 2009 Todd Zullinger <tmz@pobox.com> - 0.8.1-1
- Initial package
