#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate repeated shared-cache production imports and observed resource budgets.

The first released read is the warm-up baseline. An explicit resident-growth
budget may be supplied; the default permits four extra descriptors. These are diagnostic
acceptance bounds, not a guarantee of cache retention, latency, or allocator RSS
recovery. The dependency/source identity belongs in the accompanying receipt.
"""
import argparse
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'single_profile', Path(__file__).with_name('validate-production-metadata-memory-profile.py'))
single = importlib.util.module_from_spec(spec)
spec.loader.exec_module(single)


def validate(rows, expected_count, import_count, max_growth_bytes=None,
             max_descriptor_growth=4):
    single.integer(expected_count, 'input count', 1)
    single.integer(import_count, 'import count', 2)
    if import_count > 1_000:
        raise ValueError('Import count exceeds 1000')
    if max_growth_bytes is not None:
        single.integer(max_growth_bytes, 'resident growth budget')
    single.integer(max_descriptor_growth, 'descriptor growth budget')
    if len(rows) != expected_count:
        raise ValueError(f'Expected {expected_count} reimport records, got {len(rows)}')
    indices, processes = [], []
    for row in rows:
        indices.append(single.integer(row['inputIndex'], 'input index'))
        processes.append(single.integer(row['processIdentifier'], 'process identifier', 1))
        if not isinstance(row['file'], str) or not row['file']:
            raise ValueError('Missing input filename')
        input_bytes = single.integer(row['inputFileBytes'], 'input bytes', 1)
        single.validate_snapshot(row['metadata'], input_bytes)
        if row['inputStrategy'] != 'distinctDirectorySymlinkURLsPreservingSidecars':
            raise ValueError('Unexpected reimport input strategy')
        if single.integer(row['importCount'], 'recorded import count', 2) != import_count:
            raise ValueError('Unexpected import count')
        single.integer(row['sampleIntervalMilliseconds'], 'sample interval', 1)
        initial = single.integer(row['initialResidentBytes'], 'initial resident bytes', 1)
        lifetime = single.integer(row['initialLifetimePeakResidentBytes'], 'initial lifetime peak', 1)
        initial_fds = single.integer(row['initialOpenDescriptors'], 'initial descriptors', 1)
        if lifetime < initial:
            raise ValueError('Initial lifetime peak is below resident memory')
        single.number(row['revisitWallSeconds'], 'revisit wall time', positive=True)
        if row['revisitParity'] is not True:
            raise ValueError('Earliest URL revisit changed metadata')
        imports = row['imports']
        if not isinstance(imports, list) or len(imports) != import_count:
            raise ValueError('Missing reimport observations')
        released, descriptors = [], []
        for index, observation in enumerate(imports):
            if single.integer(observation['importIndex'], 'import index') != index:
                raise ValueError('Missing, duplicate, or unsorted import indices')
            single.integer(observation['sampleCount'], 'sample count', 1)
            for key in ('loadWallSeconds', 'cachedReadWallSeconds'):
                single.number(observation[key], key, positive=True)
            if observation['cacheParity'] is not True or observation['baselineParity'] is not True:
                raise ValueError('Reimport/cached metadata differs from the complete baseline model')
            before, peak, after, release = [single.integer(observation[key], key, 1) for key in (
                'beforeLoadResidentBytes', 'sampledPeakResidentBytes',
                'afterLoadResidentBytes', 'afterLocalReleaseResidentBytes')]
            if peak < max(before, after):
                raise ValueError('Sampled peak does not cover the uncached load')
            loaded_peak, released_peak = [single.integer(observation[key], key, 1) for key in (
                'afterLoadLifetimePeakResidentBytes', 'afterLocalReleaseLifetimePeakResidentBytes')]
            if not lifetime <= loaded_peak <= released_peak or loaded_peak < after or released_peak < release:
                raise ValueError('Lifetime peak decreased or is below resident memory')
            lifetime = released_peak
            released.append(release)
            descriptors.append(single.integer(observation['afterLocalReleaseOpenDescriptors'], 'descriptors', 1))
        revisit_resident = single.integer(row['afterRevisitResidentBytes'], 'revisit resident bytes', 1)
        revisit_peak = single.integer(row['afterRevisitLifetimePeakResidentBytes'], 'revisit lifetime peak', 1)
        revisit_fds = single.integer(row['afterRevisitOpenDescriptors'], 'revisit descriptors', 1)
        if revisit_peak < max(lifetime, revisit_resident):
            raise ValueError('Revisit lifetime peak decreased or is below resident memory')
        released.append(revisit_resident)
        descriptors.append(revisit_fds)
        # Apply the resident budget to every post-warmup release, so a transient
        # middle-cycle accumulation cannot be hidden by the final observation.
        growth = max(released) - released[0]
        descriptor_growth = max(descriptors) - initial_fds
        if max_growth_bytes is not None and growth > max_growth_bytes:
            raise ValueError(f'Resident growth after warmup exceeds budget: {growth} > {max_growth_bytes}')
        if descriptor_growth > max_descriptor_growth:
            raise ValueError(f'Open descriptor growth exceeds budget: {descriptor_growth} > {max_descriptor_growth}')
    if sorted(indices) != list(range(expected_count)):
        raise ValueError('Missing or duplicate input indices')
    if len(set(processes)) != expected_count:
        raise ValueError('Each input must run in a fresh process')
    return sorted(rows, key=lambda row: row['inputIndex'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact_directory', type=Path)
    parser.add_argument('input_count', type=int)
    parser.add_argument('import_count', type=int)
    parser.add_argument('--max-resident-growth-mib', type=int)
    parser.add_argument('--max-descriptor-growth', type=int, default=4)
    args = parser.parse_args()
    # Clear earlier receipts before reading observations or checking budgets.
    # Failed revalidation must never leave a previously passing summary behind.
    for filename in ('summary.json', 'validation.json'):
        (args.artifact_directory / filename).unlink(missing_ok=True)
    rows = []
    for path in (args.artifact_directory / 'attachments').rglob('*'):
        if path.is_file():
            for line in path.read_text(errors='replace').splitlines():
                if line.startswith('PRODUCTION_METADATA_REIMPORT_PROFILE '):
                    rows.append(json.loads(line.removeprefix('PRODUCTION_METADATA_REIMPORT_PROFILE ')))
    rows = validate(rows, args.input_count, args.import_count,
                    None if args.max_resident_growth_mib is None else args.max_resident_growth_mib * 1024 * 1024,
                    args.max_descriptor_growth)
    (args.artifact_directory / 'summary.json').write_text(json.dumps(rows, indent=2, allow_nan=False) + '\n')
    validation = {
        'inputCount': args.input_count, 'importCountPerInput': args.import_count,
        'maximumResidentGrowthBytesAfterFirstRelease': None if args.max_resident_growth_mib is None
            else args.max_resident_growth_mib * 1024 * 1024,
        'maximumOpenDescriptorGrowth': args.max_descriptor_growth,
        'passed': True,
    }
    (args.artifact_directory / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n')
    for row in rows:
        print(json.dumps(row, sort_keys=True, allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except (KeyError, TypeError, ValueError, OSError) as error:
        raise SystemExit(f'Invalid production metadata reimport profile: {error}') from error
