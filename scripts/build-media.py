#!/usr/bin/env python3
"""Reproducible static media tools; no vendor binary blobs or GPL-only codecs."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import platform
from dependency_manifest import Manifest

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Manifest()
RELEASE = json.loads((ROOT / 'Config/Release.json').read_text())
RECIPE = MANIFEST.fingerprint(['ffmpeg', 'lame', 'opus'], Path(__file__).read_bytes() + RELEASE['minimum_macos'].encode())

def run(args, cwd, env, log):
    with log.open('ab') as output:
        output.write(('\n$ ' + ' '.join(map(str, args)) + '\n').encode())
        result = subprocess.run(list(map(str, args)), cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text(errors='replace')[-6000:])
        raise SystemExit(f'Build failed; see {log}')

def build(arch):
    workspace = ROOT / '.build/media' / arch / RECIPE
    prefix = workspace / 'prefix'
    prefix.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    flags = f'-arch {arch} -mmacosx-version-min={RELEASE["minimum_macos"]} -isysroot {sdk}'
    env = dict(os.environ, CC='clang', CFLAGS=flags, LDFLAGS=flags,
               PKG_CONFIG_PATH=str(prefix / 'lib/pkgconfig'), PKG_CONFIG_LIBDIR=str(prefix / 'lib/pkgconfig'))
    jobs = str(min(os.cpu_count() or 4, 8))
    log = workspace / 'build.log'
    for name, extra in [
        ('lame', ['--disable-frontend', '--disable-decoder', '--disable-dependency-tracking']),
        ('opus', ['--disable-extra-programs', '--disable-doc', '--disable-intrinsics']),
    ]:
        source = MANIFEST.extract_source(name)
        target = workspace / name
        target.mkdir(exist_ok=True)
        library = prefix / ('lib/libmp3lame.a' if name == 'lame' else 'lib/libopus.a')
        if not library.exists():
            print(f'Building {name} for {arch}…', flush=True)
            host = 'aarch64-apple-darwin' if arch == 'arm64' else 'x86_64-apple-darwin'
            run([source / 'configure', f'--prefix={prefix}', f'--host={host}', '--disable-shared', '--enable-static', *extra], target, env, log)
            run(['make', '-j', jobs], target, env, log)
            run(['make', 'install'], target, env, log)
    source = MANIFEST.extract_source('ffmpeg')
    target = workspace / 'ffmpeg'
    target.mkdir(exist_ok=True)
    output = ROOT / 'vendor/bin' / arch
    output.mkdir(parents=True, exist_ok=True)
    stamp = target / 'resonance-build.json'
    recipe = RECIPE
    if not stamp.exists() or json.loads(stamp.read_text()).get('recipe') != recipe:
        print(f'Building FFmpeg for {arch}…', flush=True)
        run([source / 'configure', f'--prefix={prefix}', '--target-os=darwin', f'--arch={arch}',
             '--enable-cross-compile', '--cc=clang', '--disable-autodetect', '--disable-shared', '--enable-static',
             '--disable-everything', '--enable-ffmpeg', '--enable-ffprobe',
             '--enable-protocol=file,http,https,tcp,tls,crypto',
             '--enable-demuxer=mov,matroska,mp3,ogg,flac,wav,aac,mpegts,hls',
             '--enable-muxer=mp3,ipod,mp4,matroska,webm,opus,flac,wav,ogg',
             '--enable-decoder=aac,mp3,mp3float,opus,vorbis,flac,alac,pcm_s16le,pcm_s24le,pcm_s32le',
             '--enable-encoder=aac,libmp3lame,libopus,flac,pcm_s16le',
             '--enable-parser=h264,hevc,av1,vp9,aac,mpegaudio,opus,vorbis,flac',
             '--enable-filter=aresample,aformat,anull,atrim,asetpts',
             '--enable-bsf=aac_adtstoasc,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,av1_metadata',
             '--disable-doc', '--disable-debug', '--disable-ffplay', '--disable-x86asm', '--disable-vulkan',
             '--enable-securetransport', '--enable-libmp3lame', '--enable-libopus',
             '--pkg-config-flags=--static', f'--extra-cflags={flags} -I{prefix}/include',
             f'--extra-ldflags={flags} -L{prefix}/lib'], target, env, log)
        run(['make', '-j', jobs, 'ffmpeg', 'ffprobe'], target, env, log)
        stamp.write_text(json.dumps({'recipe': recipe, 'architecture': arch}))
    for name in ['ffmpeg', 'ffprobe']:
        shutil.copy2(target / name, output / name)
        (output / name).chmod(0o755)
    licenses = ROOT / 'vendor/licenses'
    for path, name in [(source / 'COPYING.LGPLv2.1', 'FFmpeg-LGPLv2.1.txt'),
                       (MANIFEST.extract_source('lame') / 'COPYING', 'LAME-LGPL.txt'),
                       (MANIFEST.extract_source('opus') / 'COPYING', 'Opus-BSD.txt')]:
        shutil.copy2(path, licenses / name)
    with (licenses / f'ffmpeg-{arch}-build.txt').open('w') as output_file:
        if platform.machine() == arch:
            subprocess.run([str(output / 'ffmpeg'), '-version'], stdout=output_file, stderr=subprocess.STDOUT, check=True)
        else:
            output_file.write(f'FFmpeg {MANIFEST.get("ffmpeg").version} / {arch}\nBuilt by scripts/build-media.py\n')
            output_file.write((target / 'ffbuild/config.mak').read_text())
    print(f'Media tools ready: {arch}', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--arch', choices=['arm64', 'x86_64'])
    args = parser.parse_args()
    for architecture in ([args.arch] if args.arch else ['arm64', 'x86_64']): build(architecture)
