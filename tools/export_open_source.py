#!/usr/bin/env python3
"""Build a reviewable, explicitly allowlisted PalmRay source export."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    'README.md', 'OPEN_SOURCE.md', '.gitignore', 'docs/index.html',
    'Shared/HandPacket.swift',
    'HandControl/main.swift', 'HandControl/SystemPointer.swift',
    'HandControl/PointerMotion.swift', 'HandControl/ScrollGesture.swift',
    'HandControl/Info.plist', 'HandControl/build.sh', 'HandControl/README.md',
    'TrueDepthProbe/Sources/App.swift', 'TrueDepthProbe/Sources/HandSender.swift',
    'TrueDepthProbe/Info.plist', 'TrueDepthProbe/project.yml',
    'TrueDepthProbe/README.md', 'release/TrueDepthProbe.README.md',
    'release/VALIDATION.md',
    'tools/export_open_source.py',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/palmray-preview')
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output == ROOT or ROOT.is_relative_to(output):
        raise SystemExit('Choose a separate export directory, not the source root or its ancestor.')
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise SystemExit('Export destination is not empty. Use --output with a new directory.')
    archive = output.with_suffix('.zip')
    if archive.exists():
        raise SystemExit('Archive already exists. Use --output with a new name.')

    project = (ROOT / 'TrueDepthProbe/project.yml').read_text()
    build = (ROOT / 'HandControl/build.sh').read_text()
    private_values = re.findall(r'DEVELOPMENT_TEAM:\s*([A-Z0-9]{10})', project)
    private_values += re.findall(r'[A-F0-9]{40}', build)
    private_values += re.findall(r'com\.(?!example\.)[\w.]+', project)

    prepared = {}
    for name in FILES:
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            raise SystemExit(f'Missing or symlinked allowlisted file: {name}')
        text = path.read_text()
        if name == 'TrueDepthProbe/README.md':
            text = (ROOT / 'release/TrueDepthProbe.README.md').read_text()
        elif name == 'TrueDepthProbe/project.yml':
            text = re.sub(r'DEVELOPMENT_TEAM:.*', 'DEVELOPMENT_TEAM: ""', text)
            text = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER:.*',
                          'PRODUCT_BUNDLE_IDENTIFIER: com.example.PalmRayProbe', text)
        elif name == 'HandControl/Info.plist':
            text = re.sub(r'<string>com\.[^<]+</string>',
                          '<string>com.example.PalmRayHandControl</string>', text, count=1)
        elif name == 'HandControl/build.sh':
            text = re.sub(r'\$\{HAND_CONTROL_SIGNING_IDENTITY:-[^}]+\}',
                          '${HAND_CONTROL_SIGNING_IDENTITY:--}', text)
        elif name == 'HandControl/README.md':
            start = text.index('The Mac app is signed using')
            end = text.index('\n\n', start)
            text = text[:start] + ('The public preview uses an ad-hoc signature by default. '
                'Set `HAND_CONTROL_SIGNING_IDENTITY` to your own stable signing identity '
                'to preserve macOS Accessibility authorization across rebuilds. '
                'Without stable signing, macOS may require authorization again.') + text[end:]
            text = re.sub(r'The saved receiver log is in .*?Quantitative accuracy',
                          'Private session logs are not distributed. Quantitative accuracy', text)
        if any(value in text for value in private_values):
            raise SystemExit(f'Local identity value remains in {name}')
        # Concrete local identifiers, not generic example path text or source regexes.
        if re.search(r'/Users/[A-Za-z0-9_.-]+/|\b[0-9A-F]{8}-[0-9A-F]{16}\b', text):
            raise SystemExit(f'Local path or device identifier remains in {name}')
        prepared[name] = text

    output.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name, text in prepared.items():
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text)
        if destination.suffix in {'.sh', '.py'}:
            destination.chmod(0o755)
        manifest.append({'path': name, 'sha256': hashlib.sha256(text.encode()).hexdigest()})
    (output / 'MANIFEST.json').write_text(json.dumps({
        'project': 'PalmRay', 'status': 'unpublished review package; license not selected',
        'files': manifest,
        'exclusions': ['private lab notes', 'device logs', 'local signing identities',
                       'generated projects', 'compiled binaries', 'glasses protocol/tools'],
    }, indent=2) + '\n')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(output.rglob('*')):
            if path.is_file():
                bundle.write(path, output.name + '/' + str(path.relative_to(output)))
    print(f'Exported {len(manifest)} source/documentation files plus manifest.')
    print(f'Known identity/path scan: passed. Archive: {archive}')
    print('Not published. License and author credit remain unselected.')


if __name__ == '__main__':
    main()
