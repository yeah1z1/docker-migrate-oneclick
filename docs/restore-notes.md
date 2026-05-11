# Restore Notes

`docker-migrate` restores Docker objects in this order:

1. Images
2. Custom networks
3. Volumes and volume data
4. Containers
5. Network attachments
6. Containers that were running on the source host, when `--start` is used

## What is preserved

- Container image reference
- Container name
- Environment variables
- Labels
- Published ports
- Named volume mounts
- Bind mount declarations
- Restart policy
- Common resource limits
- Capabilities, security options, devices, DNS, extra hosts, tmpfs
- Custom network definitions and container network attachments

## What needs attention

- Bind mount data is not archived. Copy those host paths separately if needed.
- Database containers should be backed up at the application level when possible.
- Special network or volume plugins must exist on the target host before restore.
- Compose YAML files are not reconstructed.
- Host-level settings such as firewall rules, Docker daemon config, cron jobs, and systemd units are outside the migration archive.
