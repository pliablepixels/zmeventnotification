#!/usr/bin/env python3
"""Upgrade an existing YAML config by merging in new keys from a reference example.

Existing user values are never overwritten. Only keys present in the example
but missing from the user config are added (with their default values).

Usage:
    python3 tools/config_upgrade_yaml.py -c /etc/zm/zmeventnotification.yml -e zmeventnotification.example.yml -m managed_defaults.yml -s zmeventnotification
    python3 tools/config_upgrade_yaml.py -c /etc/zm/objectconfig.yml -e hook/objectconfig.example.yml -m managed_defaults.yml -s objectconfig
    python3 tools/config_upgrade_yaml.py -c /etc/zm/secrets.yml -e secrets.example.yml
"""

import argparse
import copy
import sys

try:
    import yaml
except ImportError:
    print("PyYAML is required: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)


def deep_merge(base, override):
    """Recursively merge *base* into *override* (in-place).

    - Keys in *override* are kept as-is (user values win).
    - Keys in *base* that are missing from *override* are added.
    - When both sides have a dict for the same key, recurse.

    Returns a list of dotted key-paths that were added.
    """
    added = []
    for key, base_val in base.items():
        if key not in override:
            override[key] = copy.deepcopy(base_val)
            added.append(str(key))
        elif isinstance(base_val, dict) and isinstance(override[key], dict):
            sub_added = deep_merge(base_val, override[key])
            added.extend('{}.{}'.format(key, s) for s in sub_added)
    return added


def resolve_dotted(d, dotted_key):
    """Resolve a dotted key path like 'fcm.fcm_v1_key' in a nested dict.
    Returns the value if found, or None if any segment is missing.
    """
    parts = dotted_key.split('.')
    cur = d
    for part in parts:
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def set_dotted(d, dotted_key, value):
    """Set a value at a dotted key path in a nested dict."""
    parts = dotted_key.split('.')
    cur = d
    for part in parts[:-1]:
        cur = cur[part]
    cur[parts[-1]] = value


def remove_dotted(d, dotted_key):
    """Remove a key at a dotted path. Returns True if removed, False if not found."""
    parts = dotted_key.split('.')
    cur = d
    for part in parts[:-1]:
        if not isinstance(cur, dict) or part not in cur:
            return False
        cur = cur[part]
    if isinstance(cur, dict) and parts[-1] in cur:
        del cur[parts[-1]]
        return True
    return False


def apply_removed_keys(user, removed_keys):
    """Remove deprecated keys from user config.
    Returns a list of dotted key-paths that were removed.
    """
    removed = []
    for dotted_key in removed_keys:
        if remove_dotted(user, dotted_key):
            removed.append(dotted_key)
    return removed


def apply_managed_defaults(user, example, managed):
    """Replace user values that match known old defaults with current example values.
    Returns a list of dotted key-paths that were updated.
    """
    updated = []
    for dotted_key, old_values in managed.items():
        user_val = resolve_dotted(user, dotted_key)
        if user_val is None:
            continue
        if user_val in old_values:
            new_val = resolve_dotted(example, dotted_key)
            if new_val is not None:
                set_dotted(user, dotted_key, new_val)
                updated.append(dotted_key)
    return updated


def main():
    parser = argparse.ArgumentParser(
        description='Upgrade a YAML config by adding new keys from a reference example')
    parser.add_argument('-c', '--config', required=True,
                        help='Path to user config YAML file (will be updated in-place)')
    parser.add_argument('-e', '--example', required=True,
                        help='Path to reference/example YAML file with latest keys')
    parser.add_argument('-o', '--output',
                        help='Write to a different file instead of updating in-place')
    parser.add_argument('--dry-run', action='store_true',
                        help='Show what would be added without writing anything')
    parser.add_argument('-m', '--managed-defaults',
                        help='Path to managed defaults YAML (keys to force-update from old defaults)')
    parser.add_argument('-s', '--section',
                        help='Section within managed defaults file to use (e.g. zmeventnotification, objectconfig)')
    args = parser.parse_args()

    with open(args.example) as f:
        example = yaml.safe_load(f)
    with open(args.config) as f:
        user = yaml.safe_load(f)

    if not example:
        print("Example file is empty or invalid YAML", file=sys.stderr)
        sys.exit(1)
    if not user:
        print("User config is empty or invalid YAML", file=sys.stderr)
        sys.exit(1)

    added = deep_merge(example, user)

    managed_updated = []
    removed = []
    if args.managed_defaults:
        with open(args.managed_defaults) as f:
            managed_all = yaml.safe_load(f) or {}
        if args.section:
            managed = managed_all.get(args.section, {})
            if not managed:
                print("Note: no managed defaults found for section '{}'".format(args.section))
            removed_keys = managed_all.get(args.section + '_removed', [])
        else:
            # Legacy: flat format without sections
            managed = managed_all
            removed_keys = []
        managed_updated = apply_managed_defaults(user, example, managed)
        if removed_keys:
            removed = apply_removed_keys(user, removed_keys)

    if not added and not managed_updated and not removed:
        print("Config is already up to date — no new keys found.")
        return

    if added:
        print("New keys added from example:")
        for key in sorted(added):
            print("  + {}".format(key))

    if managed_updated:
        print("Managed defaults updated (old default replaced with current):")
        for key in sorted(managed_updated):
            print("  * {}".format(key))

    if removed:
        print("Deprecated keys removed:")
        for key in sorted(removed):
            print("  - {}".format(key))

    if args.dry_run:
        print("\nDry run — no files written.")
        return

    out_path = args.output or args.config
    with open(out_path, 'w') as f:
        yaml.dump(user, f, default_flow_style=False, sort_keys=False,
                  allow_unicode=True)

    print("\nUpdated config written to: {}".format(out_path))


if __name__ == '__main__':
    main()
