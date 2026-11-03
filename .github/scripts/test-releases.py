#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Exercise release policy and publishing without creating GitHub releases."""

import datetime
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/build-nightly.yml'
POLICY = ROOT / '.github/scripts/release-policy.py'
spec = importlib.util.spec_from_file_location('release_policy', POLICY)
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


def step(name):
    lines = WORKFLOW.read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.strip() == '- name: ' + name)
    run = next(i for i in range(start, len(lines)) if lines[i].strip() == 'run: |')
    body = []
    for line in lines[run + 1:]:
        if line.strip() and not line.startswith(' ' * 10):
            break
        body.append(line[10:])
    script = '\n'.join(body) + '\n'
    for expression, variable in [('github.event_name', 'GITHUB_EVENT_NAME'),
                                 ('github.event.schedule', 'EVENT_SCHEDULE'),
                                 ('inputs.release', 'RELEASE_REQUESTED'),
                                 ('inputs.full', 'FULL_REQUESTED')]:
        script = script.replace('${{ ' + expression + ' }}', '${' + variable + '}')
    return script


class WorkflowTest(unittest.TestCase):
    def test_monthly_schedule(self):
        crons = [line.split("'")[1] for line in WORKFLOW.read_text().splitlines()
                 if line.strip().startswith('- cron:')]
        self.assertIn('0 0 3 * *', crons)
        self.assertNotIn('0 0 1 * *', crons)

    def test_scheduled_stable_is_a_cold_build(self):
        with tempfile.TemporaryDirectory() as name:
            output = Path(name) / 'output'
            env = os.environ | {'GITHUB_OUTPUT': str(output), 'GITHUB_EVENT_NAME': 'schedule',
                                'EVENT_SCHEDULE': '0 0 3 * *', 'RELEASE_REQUESTED': '',
                                'FULL_REQUESTED': ''}
            result = subprocess.run(['bash', '-eu', '-c', step('Determine release type')],
                                    cwd=ROOT, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            values = dict(line.split('=', 1) for line in output.read_text().splitlines())
            self.assertEqual(values['OFFICIAL'], 'yes')
            self.assertEqual(values['NIGHTLY'], 'no')
            self.assertEqual(values['INCREMENTAL'], 'no')

    def test_quiet_month_still_builds_but_quiet_nightly_skips(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            helper = root / '.github/scripts/build-needed.sh'
            helper.parent.mkdir(parents=True)
            helper.write_text('#!/bin/sh\ntouch consulted\necho no\n')
            helper.chmod(0o755)
            output = root / 'output'
            for official, expected in [('yes', 'yes'), ('no', 'no')]:
                with self.subTest(official=official):
                    output.write_text('')
                    env = os.environ | {'OFFICIAL': official, 'GITHUB_OUTPUT': str(output),
                                        'GITHUB_EVENT_NAME': 'schedule',
                                        'GITHUB_STEP_SUMMARY': str(root / 'summary')}
                    result = subprocess.run(['bash', '-eu', '-c', step('Is a build needed')],
                                            cwd=root, env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_text(), f'NEEDED={expected}\n')
                    self.assertEqual((root / 'consulted').exists(), official == 'no')


class PolicyTest(unittest.TestCase):
    def test_build_modes(self):
        for args, expected in [
            (('schedule', policy.MONTHLY_CRON), ('yes', 'no', 'no')),
            (('schedule', '0 23 * * *'), ('no', 'yes', 'yes')),
            (('workflow_dispatch', '', 'true'), ('yes', 'no', 'no')),
            (('workflow_dispatch', '', 'false', 'true'), ('no', 'yes', 'no')),
            (('workflow_dispatch',), ('no', 'yes', 'yes')),
            (('pull_request',), ('no', 'yes', 'yes')),
        ]:
            with self.subTest(args=args):
                result = policy.build_policy(*args)
                self.assertEqual(tuple(result.values()), expected)

    def test_calendar_names_and_nightly_flags(self):
        for day, version in [('2026-11-03', '26.11'), ('2026-12-03', '26.12'),
                             ('2027-01-03', '27.01')]:
            with self.subTest(day=day):
                d = datetime.date.fromisoformat(day)
                stable = policy.release_tag(True, '339', d)
                self.assertEqual(stable['title'], 'PortareOS ' + version)
                self.assertEqual(stable['tag'], f'release-{version}-{d:%Y%m%d}-339')
                self.assertEqual(stable['latest'], '--latest')
                self.assertEqual(stable['prerelease'], '')
                nightly = policy.release_tag(False, '339', d)
                self.assertEqual(nightly['tag'], f'nightly-{d:%Y%m%d}-339')
                self.assertEqual(nightly['latest'], '--latest=false')
                self.assertEqual(nightly['prerelease'], '--prerelease')

    def test_changelog_baseline_past_many_nightlies(self):
        old = {'tag_name': 'release-26.10-20261003-200', 'prerelease': False,
               'published_at': '2026-10-03T06:00:00Z'}
        nightlies = [{'tag_name': f'nightly-20261102-{i}', 'prerelease': True,
                      'published_at': '2026-11-02T06:00:00Z'} for i in range(350, 200, -1)]
        draft = dict(old, tag_name='release-draft', draft=True,
                     published_at='2026-11-03T06:00:00Z')
        self.assertEqual(policy.previous_release([nightlies[:100], nightlies[100:] + [draft, old]], True), old['tag_name'])
        self.assertEqual(policy.previous_release([nightlies, [old]], False), nightlies[0]['tag_name'])
        self.assertEqual(policy.previous_release([nightlies], True), nightlies[-1]['tag_name'])
        self.assertEqual(policy.previous_release([[]], True), '')

    def test_stable_requires_a_release_tag_and_non_prerelease_status(self):
        stable = {'tag_name': 'release-20261020-295', 'prerelease': False,
                  'published_at': '2026-10-20T15:06:09Z'}
        newer = [
            dict(stable, tag_name='nightly-20261102-340',
                 published_at='2026-11-02T11:33:21Z'),
            dict(stable, tag_name='nightly-20261102-338',
                 published_at='2026-11-02T02:39:05Z'),
            dict(stable, tag_name='release-26.11-20261101-337', prerelease=True,
                 published_at='2026-11-01T20:16:19Z'),
            dict(stable, tag_name='release-26.11-20261103-342', draft=True,
                 published_at='2026-11-03T06:00:00Z'),
            dict(stable, tag_name='cache-20261103',
                 published_at='2026-11-03T07:00:00Z'),
        ]
        self.assertEqual(policy.previous_release([newer, [stable]], True), stable['tag_name'])

    def test_first_stable_uses_oldest_published_build_despite_nightly_status(self):
        oldest = {'tag_name': 'nightly-20260904-31', 'prerelease': True,
                  'published_at': '2026-09-04T13:21:02Z'}
        newer = dict(oldest, tag_name='nightly-20261102-340', prerelease=False,
                     published_at='2026-11-02T11:33:21Z')
        ignored = [dict(oldest, tag_name='nightly-draft', draft=True,
                        published_at='2026-09-01T00:00:00Z'),
                   dict(oldest, tag_name='cache-20260901', prerelease=False,
                        published_at='2026-09-01T00:00:00Z')]
        self.assertEqual(policy.previous_release([[newer], ignored + [oldest]], True),
                         oldest['tag_name'])

    def test_subsequent_months_use_the_most_recent_stable_release(self):
        history = [{'tag_name': 'release-20261020-295', 'prerelease': False,
                    'published_at': '2026-10-20T15:06:09Z'}]
        for version, day, run in [('26.11', '20261103', '342'),
                                  ('26.12', '20261203', '400'),
                                  ('27.01', '20270103', '450')]:
            with self.subTest(version=version):
                date = datetime.datetime.strptime(day, '%Y%m%d').date().isoformat()
                stable = {'tag_name': f'release-{version}-{day}-{run}',
                          'prerelease': False, 'published_at': f'{date}T06:00:00Z'}
                nightly = dict(stable, tag_name=f'nightly-{day}-{int(run) + 1}',
                               published_at=f'{date}T07:00:00Z')
                history.insert(0, stable)
                pages = [[nightly], list(reversed(history))]
                self.assertEqual(policy.previous_release(pages, True), stable['tag_name'])
                self.assertEqual(policy.previous_release(pages, False), nightly['tag_name'])


class PublishTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='portare-release-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        scripts = self.root / '.github/scripts'
        scripts.mkdir(parents=True)
        shutil.copyfile(POLICY, scripts / POLICY.name)
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
with open('calls.jsonl', 'a') as f:
    f.write(json.dumps(args) + '\\n')
if args[0] == 'api':
    print(os.environ['TEST_RELEASES'])
elif args[:2] != ['release', 'create']:
    raise SystemExit('Unexpected gh command')
''')
        gh.chmod(0o755)
        self.env = os.environ | {'PATH': str(bin_dir) + os.pathsep + os.environ['PATH'],
                                 'GITHUB_REPOSITORY': 'portare-ch/portareos',
                                 'GITHUB_SHA': 'a' * 40, 'GITHUB_REF_NAME': 'next',
                                 'GITHUB_SERVER_URL': 'https://github.com',
                                 'TEST_RELEASES': json.dumps([[{
                                     'tag_name': 'release-20261003-200',
                                     'published_at': '2026-10-03T06:00:00Z',
                                     'prerelease': False}]])}
        self.tar = self.root / 'PortareOS-SM8550.aarch64-20261103.tar'
        self.tar.write_bytes(b'update fixture')
        import hashlib
        self.sum = self.tar.with_name(self.tar.name + '.sha256')
        self.sum.write_text(hashlib.sha256(self.tar.read_bytes()).hexdigest() + '  ' + self.tar.name + '\n')

    def publish(self, official=True):
        values = policy.release_tag(official, '339', datetime.date(2026, 11, 3))
        env = self.env | {'OFFICIAL': 'yes' if official else 'no',
                          'TAG': values['tag'], 'TITLE': values['title'],
                          'LATEST': values['latest'], 'PRERELEASE': values['prerelease']}
        return subprocess.run(['bash', '-euo', 'pipefail', '-c', step('Publish')],
                              cwd=self.root, env=env, capture_output=True, text=True)

    def test_stable_publication(self):
        releases = json.loads(self.env['TEST_RELEASES'])
        releases.insert(0, [{'tag_name': 'nightly-20261102-340', 'prerelease': False,
                             'published_at': '2026-11-02T11:33:21Z'}])
        self.env['TEST_RELEASES'] = json.dumps(releases)
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in (self.root / 'calls.jsonl').read_text().splitlines()]
        self.assertIn('--paginate', calls[0])
        args = calls[-1]
        self.assertIn('--latest', args)
        self.assertNotIn('--prerelease', args)
        self.assertEqual(args[args.index('--title') + 1], 'PortareOS 26.11')
        self.assertEqual(args[args.index('--target') + 1], 'a' * 40)
        self.assertIn('--generate-notes', args)
        self.assertEqual(args[args.index('--notes-start-tag') + 1], 'release-20261003-200')
        self.assertIn('Built from `' + 'a' * 40 + '`', (self.root / 'release-notes.md').read_text())

    def test_first_stable_passes_historical_baseline_to_github(self):
        self.env['TEST_RELEASES'] = json.dumps([
            [{'tag_name': 'nightly-20261102-340', 'prerelease': False,
              'published_at': '2026-11-02T11:33:21Z'}],
            [{'tag_name': 'nightly-20260904-31', 'prerelease': True,
              'published_at': '2026-09-04T13:21:02Z'}],
        ])
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        args = json.loads((self.root / 'calls.jsonl').read_text().splitlines()[-1])
        self.assertEqual(args[args.index('--notes-start-tag') + 1], 'nightly-20260904-31')

    def test_nightly_cannot_take_latest(self):
        result = self.publish(False)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads((self.root / 'calls.jsonl').read_text().splitlines()[-1])
        self.assertIn('--latest=false', args)
        self.assertIn('--prerelease', args)

    def test_corrupt_asset_refuses_publication(self):
        self.tar.write_bytes(b'corrupted after checksumming')
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_duplicate_asset_refuses_publication(self):
        other = self.root / 'another-artifact'
        other.mkdir()
        (other / self.tar.name).write_bytes(self.tar.read_bytes())
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Duplicate basenames', result.stderr)
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_empty_artifacts_refuse_publication(self):
        self.tar.unlink()
        self.sum.unlink()
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_first_published_build(self):
        self.env['TEST_RELEASES'] = '[[]]'
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads((self.root / 'calls.jsonl').read_text().splitlines()[-1])
        self.assertIn('--generate-notes', args)
        self.assertNotIn('--notes-start-tag', args)

    def test_existing_updater_accepts_calendar_release_tag(self):
        source = (ROOT / 'packages/portareos/sources/scripts/portareos-update').read_text()
        function = source[source.index('online_releases() {'):source.index('# Decides whether the newest release')]
        release = {'tag_name': 'release-26.11-20261103-339', 'draft': False,
                   'body': 'Built from `' + 'a' * 40 + '` on `next`.',
                   'assets': [{'name': self.tar.name, 'size': 14,
                               'browser_download_url': 'https://example.com/update.tar'},
                              {'name': self.sum.name,
                               'browser_download_url': 'https://example.com/update.tar.sha256'}]}
        script = 'curl() { printf "%s" "$TEST_RELEASES"; }\n' + function + '\nonline_releases release\n'
        env = self.env | {'TEST_RELEASES': json.dumps([release]), 'UPDATE_API': 'unused',
                          'HW_DEVICE': 'SM8550', 'HW_ARCH': 'aarch64'}
        result = subprocess.run(['bash', '-eu', '-c', script], cwd=self.root, env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        fields = result.stdout.strip().split('\t')
        self.assertEqual(fields[0], release['tag_name'])
        self.assertEqual(fields[1], '20261103')
        self.assertEqual(fields[2], 'a' * 40)
        self.assertEqual(fields[-1], '339')


if __name__ == '__main__':
    unittest.main()
