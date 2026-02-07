#!/usr/bin/env python3
"""Migrate zmeventnotification.ini / secrets.ini to YAML format.

Usage:
    python3 tools/es_config_migrate_yaml.py -c /etc/zm/zmeventnotification.ini -o /etc/zm/zmeventnotification.yml
    python3 tools/es_config_migrate_yaml.py --secrets -c /etc/zm/secrets.ini -o /etc/zm/secrets.yml
"""

import argparse
import re
import sys
from configparser import ConfigParser

try:
    import yaml
except ImportError:
    print("PyYAML is required: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)


def parse_ini(config_path):
    """Read INI file and return ConfigParser object."""
    cp = ConfigParser(interpolation=None, inline_comment_prefixes='#')
    cp.read(config_path)
    return cp


def strip_quotes(value):
    """Strip matching surrounding quotes that ConfigParser preserves as literals."""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value


def migrate_es_config(cp):
    """Build YAML dict from a zmeventnotification.ini ConfigParser."""
    output = {}
    for section in cp.sections():
        data = {}
        for key, value in cp.items(section):
            # Replace {{template}} with ${template}
            value = re.sub(r'\{\{(\w+?)\}\}', r'${\1}', value)
            value = strip_quotes(value)
            data[key] = value
        if data:
            output[section] = data
    return output


def migrate_secrets(cp):
    """Build YAML dict from a secrets.ini ConfigParser."""
    output = {}
    if cp.has_section('secrets'):
        secrets = {}
        for key, value in cp.items('secrets'):
            secrets[key.upper()] = strip_quotes(value)
        output['secrets'] = secrets
    return output


def represent_str(dumper, data):
    """Custom representer: use block style for multiline, plain for simple strings."""
    if '\n' in data:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)


def main():
    parser = argparse.ArgumentParser(
        description='Migrate zmeventnotification.ini or secrets.ini to YAML format')
    parser.add_argument('-c', '--config', required=True,
                        help='Path to input INI file')
    parser.add_argument('-o', '--output', required=True,
                        help='Path to output YAML file')
    parser.add_argument('--secrets', action='store_true',
                        help='Migrate a secrets.ini file instead of zmeventnotification.ini')
    args = parser.parse_args()

    cp = parse_ini(args.config)

    if args.secrets:
        yaml_data = migrate_secrets(cp)
    else:
        yaml_data = migrate_es_config(cp)

    yaml.add_representer(str, represent_str)

    with open(args.output, 'w') as f:
        f.write("# Migrated from {}\n".format(args.config))
        f.write("# Please review and adjust as needed\n\n")
        yaml.dump(yaml_data, f, default_flow_style=False, sort_keys=False,
                  allow_unicode=True)

    print("Migration complete: {} -> {}".format(args.config, args.output))


if __name__ == '__main__':
    main()
