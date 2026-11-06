#!/bin/bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
if [[ $(id -u) != 0 ]]; then echo 'Run this script as root.' >&2; exit 1; fi
if [[ $# -gt 1 || ( $# -eq 1 && $1 != --log ) ]]; then echo "Usage: $0 [--log]" >&2; exit 1; fi
for cmd in nft wget python3 systemctl; do
    command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }
done
mkdir -p /var/log/rugov_blacklist
install -m 755 "$DIR/updater.sh" /var/log/rugov_blacklist/updater.sh
if [[ ${1:-} == --log ]]; then
    [[ -d /etc/rsyslog.d ]] || { echo 'Install rsyslog first.' >&2; exit 1; }
    install -m 644 "$DIR/51-iptables-rugov.conf" /etc/rsyslog.d/51-iptables-rugov.conf
    systemctl restart rsyslog
    printf 'RUGOV_LOG=1\n' > /var/log/rugov_blacklist/config
else
    printf 'RUGOV_LOG=\n' > /var/log/rugov_blacklist/config
fi
cat > /etc/systemd/system/rugov-nftables.service <<'UNIT'
[Unit]
Description=Restore RUGOV nftables blacklist
After=nftables.service
Before=network-pre.target
Wants=network-pre.target
ConditionPathExists=/var/log/rugov_blacklist/rules.nft

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /var/log/rugov_blacklist/rules.nft
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/rugov-update.service <<'UNIT'
[Unit]
Description=Update RUGOV nftables blacklist
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/var/log/rugov_blacklist/config
ExecStart=/var/log/rugov_blacklist/updater.sh
UNIT
cat > /etc/systemd/system/rugov-update.timer <<'UNIT'
[Unit]
Description=Update RUGOV blacklist daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
UNIT
. /var/log/rugov_blacklist/config
export RUGOV_LOG
/var/log/rugov_blacklist/updater.sh
systemctl daemon-reload
systemctl enable rugov-nftables.service
systemctl enable --now rugov-update.timer
# Remove the cron job installed by earlier versions.
rm -f /etc/cron.daily/rugov_updater
echo 'Installation finished successfully.'
