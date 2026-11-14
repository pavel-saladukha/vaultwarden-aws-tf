#!/usr/bin/env python3
"""Check templates without Terraform. Requires python-hcl2 and PyYAML."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import hcl2
import yaml

ROOT = Path(__file__).resolve().parents[1]


def main():
    for path in sorted(ROOT.glob('*.tf')):
        hcl2.loads(path.read_text())
    print('PASS: HCL syntax (python-hcl2; no Terraform commands)')
    locals_text = (ROOT / 'locals.tf').read_text()
    software = dict(re.findall(r'^\s+(\w+)\s*=\s*"([^"\n]*)"', locals_text, re.M))
    seen = set()
    with tempfile.TemporaryDirectory(prefix='vw-static-') as tmp:
        for path in sorted(ROOT.glob('*.tf')):
            content = path.read_text()
            for ref in re.findall(r'local\.software\.(?:versions|hashes)\.(\w+)', content):
                assert ref in software, f'{path.name}: missing software key {ref}'
            for match in re.finditer(r'templatefile\("([^"]+)",\s*\{(.*?)\}\)', content, re.S):
                name, body = match.groups()
                inputs = dict(re.findall(r'^\s*(\w+)\s*=\s*(.*?)[,]?\s*$', body, re.M))
                source = (ROOT / name).read_text()
                used = set(re.findall(r'(?<!\$)\$\{([A-Za-z_]\w*)\}', source))
                assert used == set(inputs), f'{name}: inputs differ: used={used}, supplied={set(inputs)}'
                values = {}
                for key, expression in inputs.items():
                    ref = re.search(r'local\.software\.(?:versions|hashes)\.(\w+)', expression)
                    values[key] = software[ref[1]] if ref else {
                        'full_domain_name': 'upgrade-test-dummy-warden.example.com',
                        'full_url': 'https://upgrade-test-dummy-warden.example.com',
                        'hosted_zone': 'example.com',
                        'hosted_zone_id': 'ZDUMMY',
                        'email_for_cert': 'test@example.com',
                        'enable_test_cert': '--test-cert',
                        'admin_token': 'dummy-admin-token',
                    }.get(key, 'upgrade-test-dummy-' + key.replace('_', '-'))
                rendered = re.sub(r'(?<!\$)\$\{([A-Za-z_]\w*)\}', lambda m: values[m[1]], source)
                rendered = rendered.replace('$${', '${').replace('%%{', '%{')
                target = Path(tmp) / Path(name).name
                target.write_text(rendered)
                if name.endswith('.sh'):
                    subprocess.run(['bash', '-n', str(target)], check=True)
                    if shutil.which('shellcheck'):
                        subprocess.run(['shellcheck', '--severity=warning', str(target)], check=True)
                if name == 'data/init.sh':
                    size = len(rendered.encode())
                    assert size <= 16384, f'EC2 user-data is too large: {size}'
                    print(f'PASS: rendered user-data is {size} bytes (limit 16384)')
                if name.endswith(('.yml', '.yaml')):
                    compose = yaml.safe_load(rendered)
                    image = compose['services']['vaultwarden']['image']
                    assert re.fullmatch(r'vaultwarden/server:[\w.-]+@sha256:[a-f0-9]{64}', image), image
                    assert '/etc/letsencrypt:/etc/letsencrypt:ro' in compose['services']['nginx']['volumes']
                if name == 'data/Dockerfile':
                    assert re.search(r'^FROM nginx:[\w.-]+@sha256:[a-f0-9]{64}$', rendered, re.M)
                seen.add(name)
    assert {'data/init.sh', 'data/docker-compose.yml', 'data/Dockerfile', 'data/nginx.conf', 'data/scripts/backup.sh'} <= seen
    for path in sorted((ROOT / 'data').rglob('*.sh')):
        subprocess.run(['bash', '-n', str(path)], check=True)
        if path.relative_to(ROOT).as_posix() not in seen and shutil.which('shellcheck'):
            subprocess.run(['shellcheck', '--severity=warning', str(path)], check=True)
    print('PASS: template inputs, software references, shell syntax, image pins, YAML, certificate mount')
    for component in ('docker_buildx_checksum', 'docker_compose_checksum'):
        assert re.fullmatch('[a-f0-9]{64}', software[component]), component
    print('PASS: download checksum formats')
    ec2 = (ROOT / 'ec2.tf').read_text()
    objects = set(re.findall(r'resource\s+"aws_s3_object"\s+"([^"]+)"', (ROOT / 's3.tf').read_text()))
    asg_start = ec2.index('resource "aws_autoscaling_group" "this"')
    asg = ec2[asg_start:]
    depends = re.search(r'depends_on\s*=\s*\[(.*?)\]', asg, re.S)
    assert depends, 'Missing instance startup dependencies'
    supplied = set(re.findall(r'aws_s3_object\.([\w-]+)', depends[1]))
    assert objects <= supplied, f'Missing startup object dependencies: {objects - supplied}'
    assert supplied <= objects, f'Unknown object dependencies: {supplied - objects}'
    print('PASS: all configuration uploads precede instance startup')
    launch_template = ec2[:asg_start]
    launch_depends = re.search(r'depends_on\s*=\s*\[(.*?)\]', launch_template, re.S)
    assert launch_depends and 'aws_s3_object.notifier' in launch_depends[1], 'Upload the notifier before publishing an IMDSv2 launch template'
    print('PASS: notifier upload precedes launch template publication')
    s3 = (ROOT / 's3.tf').read_text()
    source_objects = 0
    for match in re.finditer(r'^resource "aws_s3_object" "([^"]+)" \{(.*?)^\}', s3, re.M | re.S):
        name, body = match.groups()
        source = re.search(r'^\s+source\s*=\s*"([^"]+)"', body, re.M)
        if source is None:
            continue
        source_objects += 1
        fingerprint = re.search(r'^\s+source_hash\s*=\s*filesha256\("([^"]+)"\)', body, re.M)
        assert fingerprint and fingerprint[1] == source[1], f'{name}: missing content-change detection for {source[1]}'
        assert (ROOT / source[1]).is_file(), f'{name}: source file does not exist'
    assert source_objects, 'No file-backed configuration objects were checked'
    print(f'PASS: content-change detection for {source_objects} file-backed S3 objects')


if __name__ == '__main__':
    main()
