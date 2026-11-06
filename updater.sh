#!/bin/bash
set -euo pipefail

DIR=/var/log/rugov_blacklist
URL=https://github.com/C24Be/AS_Network_List/raw/main/blacklists/blacklist.txt
mkdir -p "$DIR"
tmp=$(mktemp -d "$DIR/.update.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

wget -q -O "$tmp/blacklist.txt" "$URL" || { echo 'Failed to download blacklist; existing rules remain active.' >&2; exit 1; }
python3 - "$tmp/blacklist.txt" "$tmp/rules.nft" "${RUGOV_LOG:-}" <<'PY'
import ipaddress, sys
source, output, logging = sys.argv[1:]
networks = {4: [], 6: []}
with open(source, encoding='utf-8') as f:
    for number, line in enumerate(f, 1):
        value = line.strip()
        if not value or value.startswith('#'):
            continue
        try:
            net = ipaddress.ip_network(value, strict=False)
        except ValueError:
            sys.exit(f'Invalid address on line {number}: {value}')
        networks[net.version].append(net)
if not any(networks.values()):
    sys.exit('Empty blacklist; existing rules remain active.')
with open(output, 'w', encoding='utf-8') as f:
    f.write('table inet rugov_block {\n')
    for version in (4, 6):
        elements = ', '.join(str(n) for n in ipaddress.collapse_addresses(networks[version]))
        f.write(f' set ipv{version}_blocked {{\n  type ipv{version}_addr\n  flags interval\n')
        if elements:
            f.write(f'  elements = {{ {elements} }}\n')
        f.write(' }\n')
    f.write(' chain prerouting {\n  type filter hook prerouting priority raw; policy accept;\n')
    for family, version in (('ip', 4), ('ip6', 6)):
        log = 'log prefix "Blocked RUGOV IP attempt: " ' if logging else ''
        f.write(f'  {family} saddr @ipv{version}_blocked {log}drop\n')
    f.write(' }\n}\n')
PY
# The delete and replacement are committed together, so a failed batch leaves the old table intact.
if nft list table inet rugov_block >/dev/null 2>&1; then
    printf 'delete table inet rugov_block\n' > "$tmp/apply.nft"
else
    : > "$tmp/apply.nft"
fi
cat "$tmp/rules.nft" >> "$tmp/apply.nft"
nft -f "$tmp/apply.nft"
mv "$tmp/blacklist.txt" "$DIR/blacklist.txt"
mv "$tmp/rules.nft" "$DIR/rules.nft"
printf '%s - Blacklist updated successfully\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$DIR/blacklist_updater.log"
