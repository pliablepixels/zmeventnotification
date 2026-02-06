#!/usr/bin/env python3
"""Migrate objectconfig.ini to objectconfig.yml (YAML format).

Usage:
    python3 tools/config_migrate_yaml.py -c /etc/zm/objectconfig.ini -o /etc/zm/objectconfig.yml
"""

import argparse
import ast
import re
import sys
from configparser import ConfigParser

try:
    import yaml
except ImportError:
    print("PyYAML is required: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)


# Keys that belong to known sections (flat config keys)
KNOWN_SECTIONS = ['general', 'animation', 'remote', 'object', 'face', 'alpr', 'ml']

# Legacy keys to strip from output
LEGACY_KEYS = {'use_sequence', 'detection_sequence', 'detection_mode'}

# Keys that are Python dict/list literals and need ast.literal_eval
LITERAL_KEYS = {'ml_sequence', 'stream_sequence', 'pyzm_overrides'}

# Keys that were only used for {{variable}} indirection and should be removed after expansion
INDIRECTION_ONLY_KEYS = {
    'my_model_sequence', 'disable_locks', 'match_past_detections',
    'object_detection_pattern', 'face_detection_pattern', 'alpr_detection_pattern',
    'tpu_object_weights', 'tpu_object_weights_mobiledet', 'tpu_object_labels',
    'tpu_min_confidence', 'tpu_object_framework', 'tpu_max_processes', 'tpu_max_lock_wait',
    'yolo4_object_config', 'yolo4_object_weights', 'yolo4_object_labels',
    'yolo4_object_framework', 'yolo4_object_processor',
    'gpu_max_processes', 'gpu_max_lock_wait', 'cpu_max_processes', 'cpu_max_lock_wait',
    'object_min_confidence', 'max_detection_size',
    'face_model', 'face_train_model', 'face_recognition_framework',
    'face_num_jitters', 'face_upsample_times', 'known_images_path', 'unknown_images_path',
    'unknown_face_name', 'save_unknown_faces', 'save_unknown_faces_leeway_pixels',
    'alpr_service', 'alpr_url', 'alpr_key', 'alpr_use_after_detection_only',
    'openalpr_recognize_vehicle', 'openalpr_country', 'openalpr_state',
    'openalpr_min_confidence', 'platerec_min_dscore', 'platerec_min_score',
    'platerec_regions', 'platerec_stats', 'platerec_payload', 'platerec_config'
}


def parse_ini(config_path):
    """Read INI file and return ConfigParser object."""
    cp = ConfigParser(interpolation=None, inline_comment_prefixes='#')
    cp.read(config_path)
    return cp


def collect_variables(cp):
    """Collect all flat key-value pairs that can be used as {{variable}} substitutions."""
    variables = {}
    for section in cp.sections():
        for key, value in cp.items(section):
            # Skip complex values (dicts/lists) - only simple strings can be variable definitions
            if key not in LITERAL_KEYS and not is_polygon(value):
                variables[key] = value
    return variables


def expand_variables(obj, variables, expanded_vars=None):
    """Recursively expand {{variable}} references in an object using collected variables.

    Returns (expanded_obj, set_of_expanded_variable_names).
    """
    if expanded_vars is None:
        expanded_vars = set()

    if isinstance(obj, str):
        # Find all {{variable}} patterns and expand them
        def replace_var(m):
            var_name = m.group(1)
            if var_name in variables:
                expanded_vars.add(var_name)
                return str(variables[var_name])
            else:
                # Keep unexpanded if variable not found (will warn later)
                return m.group(0)

        expanded = re.sub(r'\{\{(\w+)\}\}', replace_var, obj)
        return expanded, expanded_vars
    elif isinstance(obj, dict):
        result = {}
        for k, v in obj.items():
            new_v, expanded_vars = expand_variables(v, variables, expanded_vars)
            result[k] = new_v
        return result, expanded_vars
    elif isinstance(obj, list):
        result = []
        for item in obj:
            new_item, expanded_vars = expand_variables(item, variables, expanded_vars)
            result.append(new_item)
        return result, expanded_vars
    elif isinstance(obj, tuple):
        result = []
        for item in obj:
            new_item, expanded_vars = expand_variables(item, variables, expanded_vars)
            result.append(new_item)
        return tuple(result), expanded_vars
    return obj, expanded_vars


def find_unexpanded_variables(obj):
    """Find any remaining {{variable}} patterns that weren't expanded."""
    unexpanded = set()

    if isinstance(obj, str):
        for m in re.finditer(r'\{\{(\w+)\}\}', obj):
            unexpanded.add(m.group(1))
    elif isinstance(obj, dict):
        for v in obj.values():
            unexpanded.update(find_unexpanded_variables(v))
    elif isinstance(obj, (list, tuple)):
        for item in obj:
            unexpanded.update(find_unexpanded_variables(item))

    return unexpanded


def safe_eval(value):
    """Try to evaluate a Python literal string; return as-is on failure.

    Handles {{template_var}} by temporarily replacing them with placeholder
    strings so ast.literal_eval can parse the structure.
    """
    if not value or not value.strip():
        return None
    text = value.strip()

    # Replace {{template_var}} with placeholder strings for parsing,
    # then restore them in the resulting structure.
    # Handle both quoted ('{{var}}') and unquoted ({{var}}) cases.
    placeholders = {}
    counter = [0]

    def _replace_quoted(m):
        quote = m.group(1)
        template_token = m.group(2)
        key = '__TMPL_{}__'.format(counter[0])
        counter[0] += 1
        placeholders[key] = template_token
        return "{0}{1}{0}".format(quote, key)

    def _replace_bare(m):
        token = m.group(0)
        key = '__TMPL_{}__'.format(counter[0])
        counter[0] += 1
        placeholders[key] = token
        return "'{}'".format(key)

    # First handle quoted templates: '{{var}}' or "{{var}}"
    substituted = re.sub(r"""(['"])(\{\{\w+?\}\})\1""", _replace_quoted, text)
    # Then handle remaining bare (unquoted) templates: {{var}}
    substituted = re.sub(r'\{\{\w+?\}\}', _replace_bare, substituted)

    try:
        result = ast.literal_eval(substituted)
    except (ValueError, SyntaxError):
        return value

    # Restore {{template_var}} tokens in the parsed structure
    def _restore(obj):
        if isinstance(obj, str):
            return placeholders.get(obj, obj)
        elif isinstance(obj, dict):
            return {_restore(k): _restore(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [_restore(item) for item in obj]
        elif isinstance(obj, tuple):
            return tuple(_restore(item) for item in obj)
        return obj

    return _restore(result) if placeholders else result


def is_polygon(value):
    """Check if a value looks like polygon coordinates (e.g. '306,356 1003,341 ...')."""
    parts = value.strip().split(' ')
    if len(parts) < 3:
        return False
    for part in parts:
        coords = part.split(',')
        if len(coords) != 2:
            return False
        try:
            int(coords[0])
            int(coords[1])
        except ValueError:
            return False
    return True


def migrate_section(cp, section_name):
    """Extract key-value pairs from an INI section, skipping legacy keys."""
    result = {}
    if not cp.has_section(section_name):
        return result
    for key, value in cp.items(section_name):
        if key in LEGACY_KEYS:
            continue
        if key in LITERAL_KEYS:
            result[key] = safe_eval(value)
        else:
            result[key] = value
    return result


def migrate_monitor(cp, section_name):
    """Parse a monitor-<id> section into the new YAML structure.

    Separates polygon coords, zone detection patterns, and config overrides.
    """
    overrides = {}
    zones = {}
    zone_patterns = {}

    for key, value in cp.items(section_name):
        if key in LEGACY_KEYS:
            continue

        if key.endswith('_zone_detection_pattern'):
            zone_name = key.rsplit('_zone_detection_pattern', 1)[0]
            zone_patterns[zone_name] = value
        elif is_polygon(value):
            zones[key] = {'coords': value}
        elif key in LITERAL_KEYS:
            overrides[key] = safe_eval(value)
        else:
            overrides[key] = value

    # Attach detection patterns to their zones
    for zone_name, pattern in zone_patterns.items():
        if zone_name in zones:
            zones[zone_name]['detection_pattern'] = pattern
        else:
            # Pattern for a zone not defined here (maybe a ZM zone)
            zones[zone_name] = {'detection_pattern': pattern}

    if zones:
        overrides['zones'] = zones

    return overrides


def remove_indirection_keys(obj, keys_to_remove):
    """Remove keys that were only used for {{variable}} indirection."""
    if isinstance(obj, dict):
        return {k: remove_indirection_keys(v, keys_to_remove)
                for k, v in obj.items() if k not in keys_to_remove}
    elif isinstance(obj, list):
        return [remove_indirection_keys(item, keys_to_remove) for item in obj]
    return obj


def build_yaml(cp):
    """Build the full YAML dict from a parsed INI ConfigParser.

    Returns (yaml_dict, expanded_vars, unexpanded_vars).
    """
    output = {}

    for section in KNOWN_SECTIONS:
        data = migrate_section(cp, section)
        if data:
            output[section] = data

    # Handle monitor sections
    monitors = {}
    for section in cp.sections():
        if section.startswith('monitor-'):
            mid = section.split('monitor-', 1)[1]
            try:
                mid = int(mid)
            except ValueError:
                pass
            monitors[mid] = migrate_monitor(cp, section)

    if monitors:
        output['monitors'] = monitors

    # Collect variables and expand {{variable}} references
    variables = collect_variables(cp)
    output, expanded_vars = expand_variables(output, variables)

    # Find any unexpanded variables (missing definitions)
    unexpanded_vars = find_unexpanded_variables(output)

    # Remove keys that were only used for indirection and have been expanded
    keys_to_remove = INDIRECTION_ONLY_KEYS & expanded_vars
    output = remove_indirection_keys(output, keys_to_remove)

    return output, expanded_vars, unexpanded_vars


def represent_str(dumper, data):
    """Custom representer: use block style for multiline, plain for simple strings."""
    if '\n' in data:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)


def main():
    parser = argparse.ArgumentParser(description='Migrate objectconfig.ini to YAML format')
    parser.add_argument('-c', '--config', required=True, help='Path to input objectconfig.ini')
    parser.add_argument('-o', '--output', default='objectconfig.yml', help='Path to output YAML file (default: objectconfig.yml)')
    args = parser.parse_args()

    cp = parse_ini(args.config)
    yaml_data, expanded_vars, unexpanded_vars = build_yaml(cp)

    yaml.add_representer(str, represent_str)

    with open(args.output, 'w') as f:
        f.write("# Migrated from {}\n".format(args.config))
        f.write("# Please review and adjust as needed\n\n")
        yaml.dump(yaml_data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print("Migration complete: {} -> {}".format(args.config, args.output))

    if expanded_vars:
        print("\nExpanded {{{{variable}}}} references ({} variables):".format(len(expanded_vars)))
        for var in sorted(expanded_vars):
            print("  - {{{{{}}}}}".format(var))

    if unexpanded_vars:
        print("\nWARNING: The following {{{{variable}}}} references could not be expanded")
        print("(no definition found in config). Please manually fix these in the output:")
        for var in sorted(unexpanded_vars):
            print("  - {{{{{}}}}}".format(var))


if __name__ == '__main__':
    main()
