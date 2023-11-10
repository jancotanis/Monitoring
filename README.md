# Monitoring
Monitoring scripts for saas solutions


## System Configuration
Use environment variables to setup various SAAS connection parameters. These can also be put on the filesystem using a `.env` file. 

### Cloudally
Connection to Skykick partner portal api https://api.cloudally.com/...
````
CLOUDALLY_CLIENT_ID=7685b144-fe1b-4795-b38f-9a7ec6c7a1f8
CLOUDALLY_CLIENT_SECRET=BdaonZti8jn_i8jn
CLOUDALLY_USER=john.doe@acme.com
CLOUDALLY_PASSWORD=your_password_here
````

### Skykick
Connection to Skykick partner portal https://backup.skykick.com/partner/cloud-backup/manager#/
````
SKYKICK_CLIENT_ID=834hdfs-kgsj54rg-hkbvfiu-rve984
SKYKICK_CLIENT_SECRET=834hdfskgsj54rghkbvfiurve984
````

### Sophos
Connection to Sophos partner portal https://https://partners.sophos.com/
````
SOPHOS_CLIENT_ID=834hdfs-kgsj54rg-hkbvfiu-rve984
SOPHOS_CLIENT_SECRET=834hdfskgsj54rghkbvfiurve984
````

### VEEAM
Connection to VEEAM service provider console. This is vendor specific.
````
VEEAM_API_HOST=https://portal.host.com
VEEAM_API_KEY=834hdfskgsj54rghkbvfiurve984
````

### Zabbix
Connection to ZAbbix servicer api. This is location specific.
````
ZABBIX_API_HOST=https://api.your-zabbix-host.com
ZABBIX_API_KEY=d73e81e7e7e3b5f57f10539defe64c71fa
````

### Helpdesk system
Connection to Zammad, this is vendor specific.
```
ZAMMAN_HOST=https://helpdesk.xxxx.nl/
ZAMMAD_OAUTH_TOKEN=834hdfskgsj54rghkbvfiurve984
ZAMMAD_GROUP=Monitoring
ZAMMAD_CUSTOMER=john.doe@acme.com
```

## Application configuration
Application configuration is stored in `monitoring.cfg`. The document will be automatically extended based on the 
entries within the various SAAS services. The entries will be merged based on the account description. 
For each entry you may select if malware detection and/or backups needs to be checked. 

Currently malware is only supported for Sophos portal. This also scans for connection issues in VPN tunnels. 
Backup checks are supported for VEEAM, Skykick and CloudAlly.


This is a yaml formatted file with the following structure:

```
---
- !ruby/struct:ConfigData
  id: 6551ef50-2917-469d-b4ae-2fddc37d5688
  description: Name of the client
  source:
  - Sophos
  sla: []
  monitor_endpoints: false
  monitor_connectivity: false
  monitor_backup: false
  monitor_dtc: false
  create_ticket: false
  notifications:
  - !ruby/struct:Notification
    type: Check authorisations
    period: Y
    triggered: 2023-09-01
  reported_alerts: []
  endpoints: 5
- !ruby/struct:ConfigData
   :
   :
```

### Keys

|Key|Description|value|
|:--|:--|:--|
|id|Unique id of the entry|string|
|description|Customer description of the setting, this is unique and used to find configuration for SAAS cleint|string|
|source|Debugging: source where entry originates from|array|
|sla|Used to report kind of SLA in place with customer. Entries in format `source-state`.|array|
|monitor_endpoints|Monitor issues with Sophos endpoints (Sophos and Zabbix)|true/false|
|monitor_connectivity|Monitor Zabbix issues|true/false|
|monitor_backup|Monitor issues with VEEAM, CloudAlly, Skykick backups|true/false|
|monitor_dtc|Client is included in Digital Trust Center alert tickets|true/false|
|create_ticket|Create ticket within Zammad in case of monitored incidents|true/false|
|reported_alerts|Alerts that have been created a ticket for|
|endpoints|Debugging: Number of sophos endpoints found|
|reported_alerts|Ids of alerts that have been reported to the ticket system. This to prevent duplicate entries.|

### Notifications
Each customer entry can have a number of notifications. These are triggered on specific interval.
|Key|Description|value|
|:--|:--|:--|
|task|Task identifier what to do|Text, use quotes '"' when task name has spaces|
|interval|What interval do the notifications be triggered. Select from Once, Weekly, Monthly, Quarterly,Yearly|O,W,M,Q,Y|
|triggered|Last time it was triggered, this date can be in the future| YYYY-MM-DD|

## Script run options
Script can be run with ruby interpreter.
````
ruby Monitoring.rb [options]
````
Some additional options apply

|Parameter|Description|
|:--|:--|
|-s --sla|Report SLA options in configuration.md file (markdown format) |
|-l --log|Log all http api requests, used for debugging connection issues|
|-n customer,interval[,date] --notification customer,task,interval[,date]|Add customer notification weekly, monthly, quarterly, yearly or once. Interval is one of 'W', 'M', 'Q', 'Y' or 'O'|
|-g[N] --garbagecollect[=N]|Remove all log files older than N days where N is 90 days if not given|
|-? -h --help|Explanation of script options|

### Examples
Add weekly reminder for backup check for customer COAS. This is triggered next time the monitoring runs.
````
ruby Monitoring.rb -n COAS,"Check week backup",W
````

Add reminder to destroy backup tapes for COAS. This is triggered once on/after 31 December 2023 .
````
ruby Monitoring.rb -n COAS,"Destroy old backup tapes",O,2023-12-31
````
