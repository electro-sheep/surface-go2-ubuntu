"""Merge our Firefox policies into /etc/firefox/policies/policies.json, keeping any others.
The snap and the deb both read this file."""
import json, os, sys

DST = '/etc/firefox/policies/policies.json'
ours = json.load(open(sys.argv[1]))['policies']
cur = json.load(open(DST)) if os.path.exists(DST) else {}
policies = cur.setdefault('policies', {})
for key, value in ours.items():
    if isinstance(value, dict) and isinstance(policies.get(key), dict):
        policies[key].update(value)
    else:
        policies[key] = value
os.makedirs(os.path.dirname(DST), exist_ok=True)
with open(DST + '.tmp', 'w') as f:
    json.dump(cur, f, indent=2)
    f.write('\n')
os.chmod(DST + '.tmp', 0o644)
os.replace(DST + '.tmp', DST)
