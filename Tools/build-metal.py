#!/usr/bin/env python3
"""Compile pinned MLX shaders for SwiftPM macOS or an Xcode iOS app bundle."""
import argparse
import concurrent.futures
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=pathlib.Path)
parser.add_argument('--sdk', choices=['macosx', 'iphoneos', 'iphonesimulator'], default='macosx')
parser.add_argument('--source', type=pathlib.Path,
                    default=root / '.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal')
parser.add_argument('--work-dir', type=pathlib.Path)
args = parser.parse_args()
source = args.source.resolve()
output = args.output.resolve() / 'mlx.metallib'
work = args.work_dir or root / f'build/metal-{args.sdk}'
target = {'macosx': 'air64-apple-macos14.0', 'iphoneos': 'air64-apple-ios26.0',
          'iphonesimulator': 'air64-apple-ios26.0-simulator'}[args.sdk]
work.mkdir(parents=True, exist_ok=True)
inputs = sorted(source.rglob('*.metal'))
if not inputs:
    sys.exit(f'Resolve mlx-swift first; no generated shaders found at: {source}')
if output.exists() and output.stat().st_mtime >= max([pathlib.Path(__file__).stat().st_mtime] + [p.stat().st_mtime for p in source.rglob('*') if p.is_file()]):
    sys.exit(0)

def compile_shader(item):
    index, path = item
    air = work / f'{index}.air'
    subprocess.run(['xcrun', '-sdk', args.sdk, 'metal', '-c', '-target', target,
                    # Match mlx-swift/xcode/xcconfig/Cmlx.xcconfig's Metal settings.
                    '-Wall', '-Wextra', '-fno-fast-math', '-Wno-c++17-extensions', '-Wno-c++20-extensions',
                    '-I', str(source), str(path), '-o', str(air)], check=True)
    return air

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    objects = list(pool.map(compile_shader, enumerate(inputs)))
output.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', '-sdk', args.sdk, 'metallib', *map(str, objects), '-o', str(output)], check=True)
print(f'Built {output}')
