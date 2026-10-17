#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read the post-gate graph offline: collect-reference-reports.py RUN_ROOT.

Reports are scanner references, including weak pointers, not ownership proofs.
The local binary graph is pinned but is not copied into the repository.
"""
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

base = Path(sys.argv[1]).resolve(strict=True)
out = Path(__file__).resolve().parent
graph = base/'final.memgraph'
assert int((base/'reference-graph-exit.txt').read_text()) == 0 and graph.is_file()
sample = json.loads((base/'soak/memory-diagnostics/cycle-3.json').read_text())
reports = {}
for row in sample['objects']:
    if not row['alive'] or row['label'] not in ('host', 'window'):
        continue
    for mode, name in [('trace', 'paths'), ('traceTree', 'tree')]:
        command = ['/usr/bin/leaks', f"--{mode}={row['address']}", str(graph)]
        result = subprocess.run(command, capture_output=True)
        assert result.returncode == 0, result.stderr.decode()
        # Confirm the graph recognizes this exact address and expected class.
        expected = b'NSHostingView<' if row['label'] == 'host' else b'NSWindow'
        assert expected in result.stdout.splitlines()[0], result.stdout[:300]
        filename = f"{row['label']}-{row['id']}-reference-{name}.txt"
        (base/filename).write_bytes(result.stdout)
        (out/(filename+'.gz')).write_bytes(gzip.compress(result.stdout, mtime=0))
        reports[filename] = hashlib.sha256(result.stdout).hexdigest()
receipt = dict(path=str(graph), size=graph.stat().st_size,
    sha256=hashlib.file_digest(graph.open('rb'), 'sha256').hexdigest(),
    command=json.loads((base/'reference-graph-command.json').read_text()), exitCode=0,
    referenceReports=reports)
(out/'reference-graph-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
