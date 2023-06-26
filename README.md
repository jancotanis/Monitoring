# Monitoring
Monitoring scripts for saas solutions


## System Configuration
Use environment variables to setup various SAAS connection parameters

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

### Helpdesk system
Connection to Zammad, this is vendor specific.
```
ZAMMAN_HOST=https://helpdesk.xxxx.nl/
ZAMMAD_OAUTH_TOKEN=834hdfskgsj54rghkbvfiurve984
ZAMMAD_GROUP=Monitoring
ZAMMAD_CUSTOMER=john.doe@acme.com
```

## Application configuration
Applciation configuration is stored in `monitoring.cfg`. This is a yaml formatted 
file with the following structure.

Example 
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
  create_ticket: false
  reported_alerts: []
  endpoints: 5
- !ruby/struct:ConfigData
   :
   :
```
The document will be automatically extended based on the 
entries within the various SAAS services based on the 
description entries will be added or combined.

Keys

|Key|Description|value|
|--|--|--|
|id|Unique id of the entry|string|
|description|Customer description of the setting, this is unique and used to find configuration for SAAS cleint|string|
|source|Debugging: source where entry originates from|array|
|sla|Used to report kind of SLA in place with customer. Entries in format <source>-<state>.|array|
|monitor_endpoints|Monitor issues with sophos endpoints|true/false|
|monitor_connectivity|Monitor issues with sophos connectivity with firewalls etc|true/false|
|monitor_backup|Monitor issues with VEEAM backups|true/false|
|create_ticket|reate ticket within Zammad in case of monitored incidents|true/false|
|reported_alerts|Alerts that have been created a ticket for|
|endpoints|Debugging: Number of sophos endpoints found|

## Script run options
Script can be run with ruby interpreter.
````
ruby Monitoring.rb
````
Some additional options apply
|Parameter|Description|
|--|--|
|-s --sla|Report SLA options |
|-? -h --help|Explanation of script options|

