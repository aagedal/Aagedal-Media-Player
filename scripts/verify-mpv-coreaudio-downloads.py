#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Download and authenticate all package binaries and retained build inputs."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlsplit, urlunsplit

spec = importlib.util.spec_from_file_location('publication', Path(__file__).with_name('prepare-mpv-coreaudio-publication.py'))
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


def redacted_url(url):
    value = urlsplit(url)
    return urlunsplit((value.scheme, value.netloc, value.path, '', ''))


def download(entry, output):
    path = output / entry['group'] / (entry['name'] + '.zip')
    path.parent.mkdir(parents=True, exist_ok=True)
    headers = path.with_suffix('.headers')
    result = subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--silent', '--show-error',
                             '--proto', '=https', '--proto-redir', '=https', '--dump-header', str(headers),
                             '--output', str(path), '--write-out', '%{http_code}\n%{url_effective}', entry['url']],
                            capture_output=True, text=True, check=True)
    status, final_url = result.stdout.split('\n', 1)
    identity = publication.identity(path)
    if identity['sha256'] != entry['sha256'] or ('sizeBytes' in entry and identity['sizeBytes'] != entry['sizeBytes']):
        raise ValueError('download identity mismatch: ' + entry['name'])
    redirects = [redacted_url(line.split(':', 1)[1].strip()) for line in headers.read_text().splitlines()
                 if line.lower().startswith('location:')]
    # Signed CDN query strings are temporary credentials, unnecessary evidence.
    headers.unlink()
    return {**entry, **identity, 'httpStatus': int(status), 'finalURL': redacted_url(final_url),
            'redirects': redirects, 'remoteAuthenticated': True}


def verify(stage, output, digest):
    if publication.sha(stage / 'publication.json') != digest:
        raise ValueError('externally retained manifest digest mismatch')
    publication.verify(stage)
    if output.exists():
        raise ValueError('download output must be new')
    output.mkdir(parents=True)
    metadata = json.loads((stage / 'publication.json').read_text())
    entries = [{'group': 'binary-targets', 'name': e['name'], 'url': e['url'], 'sha256': e['checksum']}
               for e in metadata['binaryTargets']]
    entries += [{'group': 'build-inputs', 'name': str(index) + '-' + Path(e['relativePath']).parent.name,
                 'url': e['recipeURL'], 'sha256': e['sha256'], 'sizeBytes': e['sizeBytes']}
                for index, e in enumerate(metadata['auxiliaryBuildInputs'])]
    if len(metadata['binaryTargets']) != 29 or len(metadata['auxiliaryBuildInputs']) != 20:
        raise ValueError('unexpected declared download inventory')
    receipts, errors = [], []
    with ThreadPoolExecutor(max_workers=4) as executor:
        pending = {executor.submit(download, entry, output): entry for entry in entries}
        for future in as_completed(pending):
            entry = pending[future]
            try:
                receipts.append(future.result())
                print('Verified ' + entry['group'] + '/' + entry['name'], flush=True)
            except Exception as error:
                errors.append({'name': entry['name'], 'error': str(error)})
    result = {'schemaVersion': 1, 'passed': not errors and len(receipts) == 49,
              'publicationSHA256': digest, 'downloads': sorted(receipts, key=lambda e: (e['group'], e['name'])),
              'errors': errors, 'scope': 'HTTPS downloads and pinned byte identities; runtime acceptance is separate.'}
    (output / 'download-verification.json').write_text(json.dumps(result, indent=2) + '\n')
    return result['passed']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--expected-publication-sha256', required=True)
    args = parser.parse_args()
    try:
        return 0 if verify(args.stage.resolve(), args.output.resolve(), args.expected_publication_sha256) else 1
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Download verification failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
