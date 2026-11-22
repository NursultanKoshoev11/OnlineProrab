# Host metrics

Publishes the API host's root-disk usage and available memory to CloudWatch
(`OnlineProrab/Host/<environment>`) every five minutes. Alarms are defined in
`deploy/aws/onlineprorab-storage.yaml`:

- `HostDiskFull`: root filesystem above 85%.
- `HostMemoryLow`: less than 10% memory available for 15 minutes.
- `HostMetricsMissing`: no report for 15 minutes (host down or frozen).
- `InstanceSystemCheckFailed` / `InstanceCheckFailed` (when `ApiInstanceId`
  is set): EC2 status checks with automatic recover / reboot.

All alarms notify the stack's alert topic.

Install:

1. Update the storage stack with this template (set `ApiInstanceId`) and
   attach the `HostMetricsWriterPolicyArn` output to the instance role.
2. On the host:

```bash
sudo install -m 0755 deploy/host-metrics/onlineprorab-host-metrics.sh /usr/local/bin/onlineprorab-host-metrics
sudo install -m 0644 deploy/host-metrics/onlineprorab-host-metrics.service deploy/host-metrics/onlineprorab-host-metrics.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start onlineprorab-host-metrics.service && sudo systemctl enable --now onlineprorab-host-metrics.timer
journalctl -u onlineprorab-host-metrics.service -n 20
```
