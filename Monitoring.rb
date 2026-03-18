# frozen_string_literal: true

# 1.0   Initial version of monitoring coas saas vendor portals
# 1.1.0 Implementation of weekly/monthly/yearly notifications for SLA actions
# 1.2.0 Scan digital trust center
# 1.2.1 change ticket prio DTC, remove html description. enable ticket when adding sla
# 1.3.0 use monitor connectivity cfg flag for Zabbix, ignore duplicates on DTC alerts
# 1.4.0 Tag TDC tickets in zammad with DTC
# 1.4.1 Fix Sophos issue with missing apiHost attribute
# 1.4.2 Fix Zabbix issue with missing zabbix_clock method
# 1.4.3 List notifications and add NCSC feed scanning
# 1.4.4 Code cleanup/fix lint warnings
# 1.4.5 Add monitor-script tag, use new DTC alerts feed, suppres feed items NCSC which have no critical CVEs
#       Refactor Zammad extract class
# 1.4.6 Cache both cve and ncsc scores
# 1.4.7 Fix issue with --sla and add SLA-task ticket tag
#       refactor codebase
# 1.5.0 Fix issue not removing resolved veeam alerts and add two yearly sla option
# 1.5.1 Fix issue showing device object instead of id for zabbix
# 1.6.0 Suppres integra issues which happened yesterday also
# 1.6.1 Fix issue with missing agents data in Sophos; remove obsolete rename of feedcache
# 1.7   Use Integra session api to get better error in ticket
#       Refactor monitoring notifications
# 1.8   Switch ticketer to DigiProcess
#       Add Huntres portal to report vulnerabilities
#       NinjaOne to get all organizations for reporting
#       Add option to list portal sources
# 1.9   Use NinjaOne to monitor backups
# 1.9.1 Suppress cloudally alerts older than 30 days due to artifical ids not being unique.
#
MONITOR_VERSION = '1.9.1'

$LOAD_PATH.unshift File.expand_path('../apies/wrapi/lib', __dir__)
require 'dotenv'
require 'optparse'
require_relative 'Ticketer'
require_relative 'digi_process_ticketer'
require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'SophosMonitor'
require_relative 'VeeamMonitor'
require_relative 'SkykickMonitor'
require_relative 'CloudAllyMonitor'
require_relative 'ZabbixMonitor'
require_relative 'huntress_monitor'
require_relative 'ninjaone_monitor'
require_relative 'Integra365Monitor'
require_relative 'MonitoringModel'
require_relative 'MonitoringSLA'
require_relative 'MonitoringDTC'
require_relative 'MonitoringNCSC'

def file_age(name)
  (Time.now - File.ctime(name)) / (24 * 3600)
end

def garbage_collect(days = nil)
  days ||= 90
  puts "- removing log files older #{days.to_i} days"
  Dir.glob(['*.json', '*.txt', '*.yml', '.log']).each do |filename|
    if file_age(filename) > days
      puts "  #{filename}"
      File.delete(filename)
    end
  end
end

def get_options(config, sla)
  options = {}
  o = OptionParser.new do |opts|
    opts.banner = 'Usage: Monitor.rb [options]'

    opts.on('-s', '--sla', 'Report customer SLAs to configuration.md') do |_arg|
      config.report
      exit(0)
    end
    opts.on('-t', '--tenants', 'Report all tenants to json') do |arg|
      options[:tenants] = arg
      exit(0)
    end
    opts.on('--sources', 'Report all monitoring sources') do |arg|
      options[:sources] = arg
      exit(0)
    end
    opts.on('-c', '--compact', 'Compact config file based on tenants') do |arg|
      puts '- compacting configuration is on'
      options[:compact] = arg
    end
    opts.on('-g[N]', '--garbagecollect[=N]', Float, 'Remove all files older than N days, default is 90 days') do |arg|
      garbage_collect(arg)
    end
    opts.on(
      '-n [customer,task,interval[,date]]', '--notification [customer,task,interval[,date]]', Array,
      "Add customer notification. Interval types: #{INTERVALS.keys.join(', ')}; When no parametrers given, notifications are listed."
    ) do |arg|
      if arg
        sla.add_interval_notification(arg[0].to_s.strip, arg[1].to_s.strip, arg[2].to_s.strip, arg[3])
      else
        sla.report
      end
      exit(0)
    end
    opts.on('-l', '--log', 'Log http requests') do |log|
      puts '- API logging turned on'
      options[:log] = log
    end
    opts.on_tail('-h', '-?', '--help', opts.banner) do
      puts opts
      exit(0)
    end
  end
  o.parse!
  options
rescue OptionParser::ParseError => e
  puts "ERROR: #{e}\n\n"
  puts o
  exit(-1)
end

def create_monitors(report, config, options)
  @monitors = []
  monitor_classes = [SophosMonitor, NinjaOneMonitor, HuntressMonitor, VeeamMonitor, SkykickMonitor, CloudAllyMonitor, ZabbixMonitor, Integra365Monitor]
  puts "\n[*] Initializing #{monitor_classes.length} monitors..."

  monitor_classes.each do |klass|
    @monitors << klass.new(report, config, options[:log])
    puts "    ✓ #{klass.name.gsub('Monitor', '')}"
  rescue Faraday::Error => e
    puts "    ✗ Error initializing #{klass.name}: #{e.message}"
    puts e.response[:body] if e.response
  end
  puts ''
end

def monitors_do(report, config, options, &block)
  create_monitors(report, config, options) unless @monitors
  @monitors.each do |mon|
    block.call mon
  end
end

def report_tenants(report, config, options)
  puts '- report tenants'
  monitors_do(report, config, options, &:report_tenants)
end

def report_sources(report, config, options)
  puts '- report sources'
  monitors_do(report, config, options) do |mon|
    puts mon.source
  end
end

def run_monitors(report, config, options)
  customer_alerts = {}
  first = true
  monitors_do(report, config, options) do |mon|
    puts '[*] Running monitors...' if first
    start_time = Time.now
    print "    → #{mon.source.ljust(20)} "
    customer_alerts = mon.run(customer_alerts)
    elapsed = (Time.now - start_time).round(2)
    puts "✓ (#{elapsed}s)"
    first = false
  rescue Faraday::Error => e
    puts '✗ Error'
    puts "** Error running #{mon.class.name}"
    puts e
    puts e.response&.dig(:body)
  end
  puts ''
  customer_alerts
end

puts "Monitor v#{MONITOR_VERSION} - #{Time.now}", ''

# use environment from .env if any
Dotenv.load
config = MonitoringConfig.new
sla = MonitoringSLA.new(config)
options = get_options(config, sla)
feeds = [MonitoringDTC.new(config), MonitoringNCSC.new(config)]
ticketer = DigiProcessTicketer.new(options)

File.open(FileUtil.daily_file_name('report.txt'), 'w') do |report|
  report_tenants(report, config, options) if options[:tenants]
  report_sources(report, config, options) if options[:sources]

  customer_alerts = run_monitors(report, config, options)

  # create ticket
  puts '[*] Processing alerts and creating tickets...'
  last = ''
  tickets_created = 0
  sorted = customer_alerts.values.sort_by { |cl| cl.customer.description.upcase }
  sorted.each do |cl|
    # we have alerts

    cfg = config.by_description(cl.customer.description)
    next unless cfg.create_ticket

    # remove incidents reported last run(s)
    puts cfg.description unless last.eql? cfg.description
    last = cfg.description
    cfg.reported_alerts = cl.remove_reported_incidents(cfg.reported_alerts || [])
    monitoring_report = cl.report

    next unless monitoring_report && ticketer.create_ticket(
      "Monitoring: #{cl.name}",
      monitoring_report,
      Ticketer::PRIO_NORMAL,
      cl.source
    )

    tickets_created += 1
  end

  puts "\n[*] Processing SLA notifications..."
  sla_tickets = 0
  a = sla.load_periodic_alerts
  a.each do |notification|
    next unless notification.config.create_ticket

    next unless ticketer.create_ticket(
      "#{notification.config.description}: #{notification.notification.task}",
      notification.description, Ticketer::PRIO_NORMAL,
      'SLA-task'
    )

    sla_tickets += 1
  end
  puts "    ✓ #{sla_tickets} SLA notifications" if sla_tickets.positive?

  puts "\n[*] Processing security feeds (DTC/NCSC)..."
  feed_tickets = 0
  feeds.each do |feed|
    puts "    → #{feed.source}"
    a = feed.get_vulnerabilities_list
    a.each do |vulnerability|
      prio = if vulnerability.high_priority?
               Ticketer::PRIO_HIGH
             else
               Ticketer::PRIO_NORMAL
             end
      ticket = ticketer.create_ticket(
        "Monitoring: #{vulnerability.title}",
        vulnerability.description,
        prio,
        feed.source
      )
      feed_tickets += 1 if ticket
    end
    puts "    ✓ #{a.length} vulnerabilities" if a.length.positive?
  end

  # update list of alerts
  config.compact! if options[:compact]
  config.save_config

  puts "\n[✓] Monitoring complete!"
  puts "    Alerts: #{customer_alerts.values.sum { |cl| cl.alerts.length }} total"
  puts "    Tickets: #{tickets_created} monitoring + #{sla_tickets} SLA + #{feed_tickets} security feeds"
  puts ''
end
