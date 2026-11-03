#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Release policy shared by the scheduled build and its publisher."""

import datetime
import json
import os
import re
import sys

MONTHLY_CRON = '0 0 3 * *'
VERSION = re.compile(r'^[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$')


def build_policy(event, schedule='', release='', full=''):
    official = ((event == 'workflow_dispatch' and release == 'true') or
                (event == 'schedule' and schedule == MONTHLY_CRON))
    return {'OFFICIAL': 'yes' if official else 'no',
            'NIGHTLY': 'no' if official else 'yes',
            'INCREMENTAL': 'no' if official or full == 'true' else 'yes'}


def check_version(version, official):
    """A version names a stable release: YY.MM, or YY.MM.N for a rebuild."""
    if not version:
        return
    if not official:
        raise ValueError(f'version {version} given for a nightly; set release too')
    if not VERSION.match(version):
        raise ValueError(f'version {version} is not YY.MM or YY.MM.N')


def release_tag(official, run, day, version=''):
    check_version(version, official)
    date = day.strftime('%Y%m%d')
    version = version or day.strftime('%y.%m')
    # Installed updaters extract the build date and run from release-* tags.
    tag = (f'release-{version}-{date}-{run}' if official else f'nightly-{date}-{run}')
    return {'tag': tag,
            'title': f'PortareOS {version}' if official else f'Nightly {day.isoformat()} ({run})',
            'prerelease': '' if official else '--prerelease',
            'latest': '--latest' if official else '--latest=false'}


def previous_release(pages, official):
    releases = [r for page in pages for r in page
                if not r.get('draft') and re.match(r'^(nightly|release)-', r['tag_name'])]
    releases.sort(key=lambda r: r['published_at'], reverse=True)
    candidates = [r for r in releases if not official or
                  (r['tag_name'].startswith('release-') and not r.get('prerelease'))]
    if candidates:
        return candidates[0]['tag_name']
    # The first stable release covers the published history, rather than
    # letting GitHub choose last night's prerelease as its starting point.
    return releases[-1]['tag_name'] if releases else ''


def main():
    command = sys.argv[1]
    if command == 'plan':
        values = build_policy(os.environ['GITHUB_EVENT_NAME'],
                              os.environ.get('EVENT_SCHEDULE', ''),
                              os.environ.get('RELEASE_REQUESTED', ''),
                              os.environ.get('FULL_REQUESTED', ''))
        # Checked here, so a bad version fails before the build, not after.
        values['VERSION'] = os.environ.get('VERSION_REQUESTED', '')
        check_version(values['VERSION'], values['OFFICIAL'] == 'yes')
    elif command == 'tag':
        values = release_tag(os.environ['OFFICIAL'] == 'yes',
                             os.environ['GITHUB_RUN_NUMBER'],
                             datetime.datetime.now(datetime.timezone.utc).date(),
                             os.environ.get('VERSION_REQUESTED', ''))
    elif command == 'previous':
        print(previous_release(json.load(sys.stdin), os.environ['OFFICIAL'] == 'yes'))
        return
    else:
        raise ValueError(f'Unknown command: {command}')
    for key, value in values.items():
        print(f'{key}={value}')


if __name__ == '__main__':
    main()
