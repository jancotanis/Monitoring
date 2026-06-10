# Monitoring

Ruby-based multi-vendor SaaS monitoring aggregator that collects security and backup alerts from multiple vendors and auto-creates tickets in Zammad helpdesk.

## Quick Start

```bash
# Install dependencies
bundle install

# Run monitoring
ruby Monitoring.rb

# Run tests
rake test

# Run linter
rake rubocop
```

## Supported Services

| Category | Services |
|----------|----------|
| Security | Sophos, Huntress, Zabbix |
| Backup | Veeam, CloudAlly, Skykick, Integra365 |
| Threat Intel | Digital Trust Center (DTC), NCSC |
| ticketing | Zammad, DigiProcess |

## System Configuration

Environment variables are used to configure API connections. See the detailed configuration section below.

### Environment Variables

#### CloudAlly
```bash
CLOUDALLY_CLIENT_ID=your_client_id
CLOUDALLY_CLIENT_SECRET=your_client_secret
CLOUDALLY_USER=your_email
CLOUDALLY_PASSWORD=your_password
```

#### Skykick
```bash
SKYKICK_CLIENT_ID=your_client_id
SKYKICK_CLIENT_SECRET=your_client_secret
```

#### Sophos
```bash
SOPHOS_CLIENT_ID=your_client_id
SOPHOS_CLIENT_SECRET=your_client_secret
```

#### Veeam
```bash
VEEAM_API_HOST=https://your-veeam-host.com
VEEAM_API_KEY=your_api_key
```

#### Integra365
```bash
INTEGRA365_USER=your_email
INTEGRA365_PASSWORD=your_password
```

#### Zabbix
```bash
ZABBIX_API_HOST=https://your-zabbix-host.com
ZABBIX_API_KEY=your_api_key
```

#### Huntress
```bash
HUNTRESS_API_KEY=your_api_key
HUNTRESS_API_SECRET=your_api_secret
```

#### NinjaOne
```bash
NINJA1_HOST=https://your-host.rmmservice.eu
NINJA1_CLIENT_ID=your_client_id
NINJA1_CLIENT_SECRET=your_client_secret
```

#### Zammad (ticketing)
```bash
ZAMMAD_HOST=https://your-helpdesk.com/
ZAMMAD_OAUTH_TOKEN=your_oauth_token
ZAMMAD_GROUP=Monitoring
ZAMMAD_CUSTOMER=your_customer_email
```

#### DigiProcess (alternative ticketing)
```bash
DIGIPROCESS_SECRET=your_secret
DIGIPROCESS_WEBHOOK=your_webhook
DIGIPROCESS_RELATION_NUMBER=your_relation_id
DIGIPROCESS_RELATION_EMAIL=your_email
DIGIPROCESS_SOURCE=Monitoring
```

## Application Configuration

Configuration is stored in `monitoring.cfg` (YAML format). The file is automatically populated as the system discovers tenants from each service.

### Configuration Keys

| Key | Description |
|-----|-------------|
| `id` | Unique identifier |
| `description` | Customer name (unique) |
| `source` | Array of source services |
| `sla` | SLA configuration |
| `monitor_endpoints` | Monitor endpoint issues |
| `monitor_connectivity` | Monitor connectivity |
| `monitor_backup` | Monitor backup failures |
| `monitor_dtc` | Include in DTC alerts |
| `create_ticket` | Create tickets for alerts |
| `notifications` | Scheduled notifications |
| `reported_alerts` | Track sent alerts (prevent duplicates) |

## Command-Line Options

| Option | Description |
|--------|-------------|
| `-s, --sla` | Generate SLA report |
| `-l, --log` | Log all HTTP API requests |
| `-n customer,task,interval[,date]` | Add notification |
| `-g[N], --garbagecollect[=N]` | Clean old files (default 90 days) |
| `-h, --help` | Show help |

### Examples

```bash
# Add weekly backup check notification
ruby Monitoring.rb -n "CustomerName","Check backup",W

# Add one-time task with specific date
ruby Monitoring.rb -n "CustomerName","Task name",O,2024-12-31

# Generate SLA report
ruby Monitoring.rb --sla

# Enable API logging
ruby Monitoring.rb --log

# Cleanup files older than 30 days
ruby Monitoring.rb -g 30
```

## Development

### Running Tests

```bash
# All tests
rake test

# Single test file
ruby -Itest test/config_test.rb

# Single test
rake test TEST=test/config_test.rb TESTOPTS="-n /test_0001/"
```

### Code Style

The project uses RuboCop for linting. Run before committing:

```bash
rake rubocop
```

## File Organization

```
├── *.rb                 # Main source files
├── test/                # Test files
│   └── *_test.rb
├── docs/                # Documentation
├── monitoring.cfg       # Customer configuration (git-ignored)
├── .env                 # Environment variables (git-ignored)
└── *.log               # Log files
```

## Architecture

- **Abstract Monitor Pattern**: Each service has an API wrapper (`*API.rb`) and monitor (`*Monitor.rb`)
- **Configuration**: Managed via `ConfigData` struct in `monitoring.cfg`
- **ticketing**: Zammad (primary) or DigiProcess (alternative)
- **Deduplication**: Uses `reported_alerts` to prevent duplicate tickets

## License

Internal use only.
