# Block RKN bots with nftables

This project blocks incoming IPv4 and IPv6 traffic from the [blacklist](https://github.com/C24Be/AS_Network_List/blob/main/blacklists/blacklist.txt). It uses a dedicated `inet rugov_block` nftables table and does not modify other tables.

## Installation

On a systemd-based Debian or Ubuntu system, install `nftables`, `wget`, and `python3`. Install `rsyslog` too if logging is desired. Clone this repository and run:

```sh
sudo ./install.sh
# Or, to log blocked packets:
sudo ./install.sh --log
```

The installer downloads and applies the list, schedules daily updates with a persistent systemd timer, and enables a systemd service to restore the last successfully applied rules at boot. Logging can generate large files; messages are written to `/var/log/rugov_blacklist/blacklist.log`.

Updates validate the complete list and replace the table in one nftables transaction. A failed download, invalid list, or failed nft transaction leaves the active rules unchanged. The saved rules and update log are in `/var/log/rugov_blacklist/`.

The previous iptables version may have left rules in the raw PREROUTING chains. Remove those separately when migrating; this installer does not alter existing firewall rules.

The original instructions are available in [original_instruction.pdf](original_instruction.pdf).

Run an update manually with `sudo systemctl start rugov-update.service`. Check the timer with `systemctl list-timers rugov-update.timer` and inspect update output with `journalctl -u rugov-update.service`.
