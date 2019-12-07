#  A template for monitoring Veeam & Backup Server through PowerShell.

## Requirements:
- Veeam backup server
- Powerhell
- Zabbix> = 4 versions

## It was checked for:
PowerShell v4.0, VBRS 9.5u4, Zabbix 4.2.2

## Capabilities:
### LLD Support:
- Backup
- Backup for each VM
- Backup sync
- Backup synchronization for each VM
- Backups on tape
- Managed Agent Backup
- Backup not managed agents
- Backup of unmanaged agents (for each computer)
- Repository

## Installation:
1. Import a template
2. Add regulars to Administration -> General -> Regular expressions

```
Name: VbrJsonCheck
Expression type: Result is TRUE
Expression: ^{"data":\s*?{[\s\S]+}$

Name: Veeam
Expression type: Result is TRUE
Expression: Veeam.*
```

3. Copy the script to a machine with VBRS, for example, in the ZabbixAgent folder
4. Add to zabbix_agentd.conf:

```
Timeout = 30
UserParameter = vbr [*], powershell -NoProfile -ExecutionPolicy Bypass -File "c: \ Program Files \ Zabbix Agent \ zabbix_vbr.ps1" "$ 1"
```
