#!/usr/bin/env python3
"""Build the Arch package and the Fedora RPM from one published release archive, or check that the recipes agree.

The archive is scripts/package_release.py's cedar-<version>-x86_64.tar.gz. Both
packages ship its cedar-shell/ tree byte-identical under /usr/share/cedar, the
/usr/bin/cedar wrapper and the two licence files, nothing else; every build is
verified against the archive's ARTIFACT-CONTENTS.json before it is reported.
"""
from pathlib import Path, PurePosixPath
import argparse,hashlib,json,os,re,shutil,subprocess,sys,tarfile,tempfile

ROOT=Path(__file__).resolve().parents[1]
NAME='cedar-shell'
URL='https://github.com/EMQOutlaw/Cedar-Shell'
PACKAGER='CEDAR release automation <41898282+github-actions[bot]@users.noreply.github.com>'
WRAPPER='#!/bin/sh\nexec python3 /usr/share/cedar/scripts/distribution.py "$@"\n'
LICENSE_FILES=('licenses/Omarchy-MIT.txt','docs/LICENSES.md')
# Every destination both recipes must agree on (directories and files).
INSTALLED_PATHS={'/usr/bin','/usr/bin/cedar','/usr/share/cedar','/usr/share/cedar/scripts/distribution.py',
                 '/usr/share/licenses/cedar-shell/Omarchy-MIT.txt','/usr/share/licenses/cedar-shell/LICENSES.md'}
PKGBUILD_VARIABLES={'${pkgdir}':'','$pkgdir':'','${pkgname}':NAME,'$pkgname':NAME}
SPEC_MACROS={'%{buildroot}':'','%{name}':NAME,'%{_bindir}':'/usr/bin','%{_datadir}':'/usr/share','%{_licensedir}':'/usr/share/licenses'}
SPEC_TAGS=('Name','Version','Release','Summary','License','URL','Source0','BuildArch')
SPEC_SECTIONS=('%description','%prep','%build','%install','%files','%changelog')
SPEC_UNDEFINES=('%undefine __brp_mangle_shebangs','%undefine __brp_python_bytecompile')
SCRIPTLETS=('%pre','%post','%preun','%postun','%pretrans','%posttrans')

def sha256(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def recipes(root):return {'VERSION':root/'VERSION','PKGBUILD':root/'packaging/arch/PKGBUILD','spec':root/'packaging/fedora/cedar-shell.spec','nix':root/'packaging/nix/package.nix'}
def first(pattern,text):
    match=re.search(pattern,text,re.M);return match.group(1) if match else None
def pkgbuild_version(text):return first(r'^pkgver=(\S+)$',text)
def spec_version(text):return first(r'^Version:\s*(\S+)$',text)
def spec_release(text):return first(r'^Release:\s*(\S+)$',text)
def nix_version(text):return first(r'version = "([^"]+)";',text)

def versions(root):
    """The version each recipe carries; they must all equal VERSION."""
    files=recipes(root);read=lambda key:files[key].read_text() if files[key].is_file() else ''
    return {'VERSION':read('VERSION').strip() or None,'PKGBUILD pkgver':pkgbuild_version(read('PKGBUILD')),
            'spec Version':spec_version(read('spec')),'nix version':nix_version(read('nix'))}

def checksummed_pkgbuild(text,digest):
    """The repository PKGBUILD keeps SKIP; the built and published copy carries the archive checksum."""
    new,count=re.subn(r"^sha256sums=\('SKIP'\)$",f"sha256sums=('{digest}')",text,flags=re.M)
    if count!=1:raise SystemExit("The PKGBUILD must carry exactly one sha256sums=('SKIP') line.")
    return new

def installed_paths(text,substitutions):
    """Absolute /usr destinations a recipe mentions once its variables or macros are expanded."""
    for key,value in substitutions.items():text=text.replace(key,value)
    return {found.rstrip('./') for found in re.findall(r'(?<![\w.-])/usr/[\w./-]*',text)}

def source_url(text,substitutions):
    for key,value in substitutions.items():text=text.replace(key,value)
    return first(r'(https://\S+?\.tar\.gz)',text)

def check(root=ROOT):
    """Static consistency problems between VERSION and the three recipes; empty when fine."""
    problems=[];files=recipes(root)
    for key,path in files.items():
        if not path.is_file():problems.append('Missing '+str(path.relative_to(root)))
    if problems:return problems
    found=versions(root);version=found['VERSION']
    if None in found.values() or len(set(found.values()))!=1:problems.append('Versions disagree: '+', '.join(f'{k}={v}' for k,v in found.items()))
    pkgbuild=files['PKGBUILD'].read_text();spec=files['spec'].read_text()
    if shutil.which('bash'):
        syntax=subprocess.run(['bash','-n',str(files['PKGBUILD'])],capture_output=True,text=True)
        if syntax.returncode:problems.append('PKGBUILD syntax: '+syntax.stderr.strip())
    for line,label in ((f'pkgname={NAME}','pkgname'),("arch=('any')","arch=('any')"),("license=('custom:unlicensed')","license=('custom:unlicensed')"),("sha256sums=('SKIP')","sha256sums=('SKIP') in the repository copy")):
        if not re.search('^'+re.escape(line)+'$',pkgbuild,re.M):problems.append('PKGBUILD lacks '+label)
    if re.search(r'^install=',pkgbuild,re.M):problems.append('PKGBUILD must not carry an install hook')
    for tag in SPEC_TAGS:
        if not re.search(rf'^{tag}:\s*\S',spec,re.M):problems.append('spec lacks the tag '+tag)
    for section in SPEC_SECTIONS:
        if not re.search('^'+re.escape(section)+r'\s*$',spec,re.M):problems.append('spec lacks the section '+section)
    for line in SPEC_UNDEFINES:
        if not re.search('^'+re.escape(line)+r'\s*$',spec,re.M):problems.append('spec lacks '+line)
    for scriptlet in SCRIPTLETS:
        if re.search('^'+re.escape(scriptlet)+r'\b',spec,re.M):problems.append('spec must not carry '+scriptlet)
    for pattern,label in ((rf'^Name:\s*{NAME}$','Name: '+NAME),(r'^Release:\s*\d+%\{\?dist\}$','Release: N%{?dist}'),(r'^License:\s*LicenseRef-CEDAR-Unlicensed$','License: LicenseRef-CEDAR-Unlicensed'),(r'^BuildArch:\s*noarch$','BuildArch: noarch')):
        if not re.search(pattern,spec,re.M):problems.append('spec lacks '+label)
    if version:
        expected=f'{URL}/releases/download/v{version}/cedar-{version}-x86_64.tar.gz'
        pkgbuild_url=source_url(pkgbuild,{'${pkgver}':version,'$pkgver':version,'${url}':URL,'$url':URL})
        spec_url=source_url(spec,{'%{version}':version,'%{url}':URL,'%{name}':NAME})
        if pkgbuild_url!=expected:problems.append('PKGBUILD source is not the release archive: '+str(pkgbuild_url))
        if spec_url!=expected:problems.append('spec Source0 is not the release archive: '+str(spec_url))
        release=(spec_release(spec) or '').split('%')[0]
        entry=first(r'^%changelog\n\* .* - (\S+)$',spec)
        if entry!=f'{version}-{release}':problems.append(f'spec %changelog opens with {entry}, expected {version}-{release}')
    arch_paths=installed_paths(pkgbuild,PKGBUILD_VARIABLES);rpm_paths=installed_paths(spec,SPEC_MACROS)
    if arch_paths!=rpm_paths:problems.append('PKGBUILD and spec install different paths: '+', '.join(sorted(arch_paths^rpm_paths)))
    missing=INSTALLED_PATHS-(arch_paths&rpm_paths)
    if missing:problems.append('Recipes miss required destinations: '+', '.join(sorted(missing)))
    return problems

def archive_info(tarball):
    """Validate the complete archive before passing it to native build tools."""
    with tarfile.open(tarball, 'r:gz') as tar:
        members = {}
        for member in tar.getmembers():
            name = member.name
            rel = PurePosixPath(name)
            if (not name.startswith('cedar-shell/') or '..' in rel.parts or
                    str(rel) != name or not member.isfile() or name in members or
                    member.mode not in (0o644, 0o755)):
                raise SystemExit('Unsafe or duplicate release archive entry: ' + name)
            members[name] = member
        required = {'cedar-shell/VERSION', 'cedar-shell/ARTIFACT-CONTENTS.json',
                    'cedar-shell/scripts/distribution.py', *('cedar-shell/' + rel for rel in LICENSE_FILES)}
        if not required <= members.keys():
            raise SystemExit('Release archive lacks required files.')
        version = tar.extractfile(members['cedar-shell/VERSION']).read().decode().strip()
        if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
            raise SystemExit('Invalid release VERSION: ' + version)
        contents = tar.extractfile(members['cedar-shell/ARTIFACT-CONTENTS.json']).read()
        def unique(pairs):
            result = {}
            for key, value in pairs:
                if key in result: raise SystemExit('Duplicate manifest key: ' + key)
                result[key] = value
            return result
        manifest = json.loads(contents, object_pairs_hook=unique)
        if not isinstance(manifest, dict): raise SystemExit('Invalid release manifest.')
        expected = {'cedar-shell/' + rel for rel in manifest} | {'cedar-shell/ARTIFACT-CONTENTS.json'}
        if expected != members.keys(): raise SystemExit('Archive files disagree with its manifest.')
        for rel, entry in manifest.items():
            member = members['cedar-shell/' + rel]
            data = tar.extractfile(member).read()
            if (not isinstance(entry, dict) or entry.get('bytes') != len(data) or
                    entry.get('sha256') != hashlib.sha256(data).hexdigest()):
                raise SystemExit('Archive hash or size differs from its manifest: ' + rel)
        modes = {name[len('cedar-shell/'):]:member.mode for name, member in members.items()}
    return version, manifest, contents, modes

def extract(package,destination):
    """Unpack a .pkg.tar.zst or .rpm payload into destination/tree and return that tree."""
    tree=destination/'tree';tree.mkdir()
    if package.name.endswith('.rpm') and shutil.which('rpm2archive'):
        # RPM 6 writes to stdout even for a named input, unlike RPM 4. Using
        # stdin/stdout explicitly works with both and avoids suffix assumptions.
        payload=destination/'payload.tar'
        with package.open('rb') as source,payload.open('wb') as converted:
            subprocess.run(['rpm2archive','--nocompression','-'],stdin=source,stdout=converted,check=True)
        with tarfile.open(payload) as tar:
            tar.extractall(tree, filter='data')
    elif shutil.which('bsdtar'):subprocess.run(['bsdtar','-xf',str(package),'-C',str(tree)],check=True)
    else:raise SystemExit('Inspecting packages needs bsdtar (libarchive) or, for RPMs, rpm2archive.')
    return tree

def verify_package(package,manifest,contents,modes):
    """The package holds exactly the archive tree, the wrapper and the licences, byte for byte."""
    with tempfile.TemporaryDirectory(prefix='cedar-package-') as temporary:
        tree=extract(package,Path(temporary))
        found={str(path.relative_to(tree)) for path in tree.rglob('*') if path.is_file() or path.is_symlink()}
        found -= {'.PKGINFO', '.MTREE', '.BUILDINFO'}  # Only known Arch metadata is excluded.
        expected={'usr/share/cedar/'+rel for rel in manifest}|{'usr/share/cedar/ARTIFACT-CONTENTS.json','usr/bin/cedar'}|{'usr/share/licenses/cedar-shell/'+Path(rel).name for rel in LICENSE_FILES}
        if found!=expected:
            raise SystemExit('Package contents differ from the archive. Missing: '+', '.join(sorted(expected-found)[:10] or ['none'])+'. Unexpected: '+', '.join(sorted(found-expected)[:10] or ['none']))
        for rel,entry in manifest.items():
            file=tree/'usr/share/cedar'/rel
            if file.is_symlink() or sha256(file)!=entry['sha256']:raise SystemExit('Package file differs from the archive: '+rel)
            if bool(file.stat().st_mode&0o111)!=bool(modes[rel]&0o111):raise SystemExit('Executable bit differs from the archive: '+rel)
        if (tree/'usr/share/cedar/ARTIFACT-CONTENTS.json').read_bytes()!=contents:raise SystemExit('ARTIFACT-CONTENTS.json differs from the archive.')
        wrapper=tree/'usr/bin/cedar'
        if wrapper.read_bytes()!=WRAPPER.encode() or not wrapper.stat().st_mode&0o111:raise SystemExit('Unexpected /usr/bin/cedar wrapper.')
        for rel in LICENSE_FILES:
            if sha256(tree/'usr/share/licenses/cedar-shell'/Path(rel).name)!=manifest[rel]['sha256']:raise SystemExit('Licence copy differs from the archive: '+rel)

def report(paths):
    for path in paths:print(f'{path.name}  {path.stat().st_size} bytes  sha256 {sha256(path)}')

def require(*tools):
    for tool in tools:
        if not shutil.which(tool):raise SystemExit(tool+' is required and was not found on PATH.')

def build_arch(tarball,out,pkgbuild_path):
    """makepkg the checksummed PKGBUILD against the archive; copies the package, PKGBUILD and .SRCINFO to out."""
    if os.geteuid()==0:raise SystemExit('makepkg refuses to run as root; run build_packages.py arch as an unprivileged user (CI creates a builder account for this).')
    require('makepkg','fakeroot','bsdtar')
    version,manifest,contents,modes=archive_info(tarball);text=pkgbuild_path.read_text()
    if pkgbuild_version(text)!=version:raise SystemExit(f'PKGBUILD pkgver {pkgbuild_version(text)} does not match the archive VERSION {version}.')
    text=checksummed_pkgbuild(text,sha256(tarball))
    with tempfile.TemporaryDirectory(prefix='cedar-makepkg-') as temporary:
        build=Path(temporary)/'build';build.mkdir();(build/'PKGBUILD').write_text(text)
        shutil.copy2(tarball,build/f'cedar-{version}-x86_64.tar.gz')
        env={**os.environ,'PACKAGER':PACKAGER,**{key:str(build/key.lower()) for key in ('PKGDEST','SRCDEST','SRCPKGDEST','LOGDEST','BUILDDIR')}}
        for key in ('PKGDEST','SRCDEST','SRCPKGDEST','LOGDEST','BUILDDIR'):Path(env[key]).mkdir()
        srcinfo=subprocess.run(['makepkg','--printsrcinfo'],cwd=build,env=env,check=True,capture_output=True,text=True).stdout
        subprocess.run(['makepkg','--force','--nodeps','--noconfirm'],cwd=build,env=env,check=True)
        packages=[path for path in Path(env['PKGDEST']).iterdir() if '.pkg.tar' in path.name and not path.name.endswith('.sig')]
        if len(packages)!=1:raise SystemExit('Expected one package from makepkg, found: '+', '.join(path.name for path in packages))
        verify_package(packages[0],manifest,contents,modes)
        out.mkdir(parents=True,exist_ok=True)
        produced=[Path(shutil.copy2(packages[0],out/packages[0].name)),out/f'{NAME}-{version}-PKGBUILD',out/f'{NAME}-{version}-SRCINFO']
        produced[1].write_text(text);produced[2].write_text(srcinfo)
    print('Arch package verified against the archive manifest ('+str(len(manifest))+' files).');report(produced)
    return produced

def build_rpm(tarball,out,spec_path):
    """rpmbuild -ba the spec against the archive; binary and source RPMs land flat in out."""
    require('rpmbuild')
    version,manifest,contents,modes=archive_info(tarball);text=spec_path.read_text()
    if spec_version(text)!=version:raise SystemExit(f'spec Version {spec_version(text)} does not match the archive VERSION {version}.')
    with tempfile.TemporaryDirectory(prefix='cedar-rpmbuild-') as temporary:
        top=Path(temporary)/'rpmbuild';sources=top/'SOURCES';results=top/'RESULTS'
        for path in (sources,results):path.mkdir(parents=True)
        shutil.copy2(tarball,sources/f'cedar-{version}-x86_64.tar.gz');spec=top/spec_path.name;shutil.copy2(spec_path,spec)
        defines=[('_topdir',top),('_sourcedir',sources),('_rpmdir',results),('_srcrpmdir',results),('packager',PACKAGER)]
        subprocess.run(['rpmbuild','-ba',str(spec),*sum((['--define',f'{key} {value}'] for key,value in defines),[])],check=True)
        rpms=sorted(results.rglob('*.rpm'))  # _rpmdir gets an arch subdirectory; publish them flat
        if not any(path.name.endswith('.noarch.rpm') for path in rpms):raise SystemExit('rpmbuild produced no noarch package.')
        out.mkdir(parents=True,exist_ok=True);produced=[]
        for path in rpms:
            if path.name.endswith('.noarch.rpm'):verify_package(path,manifest,contents,modes)
            produced.append(Path(shutil.copy2(path,out/path.name)))
        produced.append(Path(shutil.copy2(spec_path, out / f'{NAME}-{version}.spec')))
    print('RPM verified against the archive manifest ('+str(len(manifest))+' files).');report(produced)
    return produced

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__.splitlines()[0]);commands=p.add_subparsers(dest='command',required=True)
    arch=commands.add_parser('arch',help='build the Arch package with makepkg');arch.add_argument('tarball',type=Path);arch.add_argument('--out',type=Path,required=True)
    arch.add_argument('--pkgbuild',type=Path,default=ROOT/'packaging/arch/PKGBUILD')
    rpm=commands.add_parser('rpm',help='build the Fedora RPM with rpmbuild');rpm.add_argument('tarball',type=Path);rpm.add_argument('--out',type=Path,required=True)
    rpm.add_argument('--spec',type=Path,default=ROOT/'packaging/fedora/cedar-shell.spec')
    static=commands.add_parser('check',help='check VERSION, PKGBUILD, spec and nix agree');static.add_argument('--root',type=Path,default=ROOT)
    a=p.parse_args()
    if a.command=='arch':build_arch(a.tarball.resolve(),a.out.resolve(),a.pkgbuild.resolve())
    elif a.command=='rpm':build_rpm(a.tarball.resolve(),a.out.resolve(),a.spec.resolve())
    else:
        problems=check(a.root.resolve())
        for problem in problems:print('PROBLEM: '+problem)
        if problems:sys.exit(1)
        print('OK: VERSION '+versions(a.root.resolve())['VERSION']+' is carried by the PKGBUILD, the spec and the Nix package; both recipes install the same paths.')
