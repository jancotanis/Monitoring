# frozen_string_literal: true

# 1.0	Initial version of monitoring coas saas vendor portals
# 1.1.0	Implementation of weekly/monthly/yearly notifications for SLA actions
# 1.2.0	Scan digital trust center
# 1.2.1	change ticket prio DTC, remove html description. enable ticket when adding sla
# 1.3.0	use monitor connectivity cfg flag for Zabbix, ignore duplicates on DTC alerts
# 1.4.0	Tag TDC tickets in zammad with DTC
# 1.4.1	Fix Sophos issue with missing apiHost attribute
# 1.4.2	Fix Zabbix issue with missing zabbix_clock method
# 1.4.3	List notifications and add NCSC feed scanning
# 1.4.4	Code cleanup/fix lint warnings
#
MONITOR_VERSION = '1.4.4'

require 'dotenv'
require 'optparse'
require 'zammad_api'
require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'SophosMonitor'
require_relative 'VeeamMonitor'
require_relative 'SkykickMonitor'
require_relative 'CloudAllyMonitor'
require_relative 'ZabbixMonitor'
require_relative 'Integra365Monitor'
require_relative 'MonitoringModel'
require_relative 'MonitoringSLA'
require_relative 'MonitoringDTC'
require_relative 'MonitoringNCSC'

PRIO_LOW = '1 low'
PRIO_NORMAL = '2 normal'
PRIO_HIGH = '3 high'

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

    opts.on('-s', '--sla', 'Report customer SLAs') do |_arg|
      config.report
      exit 0
    end
    opts.on('-t', '--tenants', 'Report all tenants to json') do |arg|
      options[:tenants] = arg
    end
    opts.on('-c', '--compact', 'Compact config file based on tenants') do |arg|
      puts '- compacting configuration is on'
      options[:compact] = arg
    end
    opts.on('-g[N]', '--garbagecollect[=N]', Float, 'Remove all files older than N days, default is 90 days') do |arg|
      garbage_collect(arg)
    end
    #	opts.on("-r", "--reload", "Reload cached files") do |arg|
    #		options[:reload] = arg
    #	end
    opts.on(
      '-n [customer,task,interval[,date]]', '--notification [customer,task,interval[,date]]', Array,
      'Add customer notification of list them if no arguments given'
    ) do |arg|
      if arg
        options[:customer]     = arg[0].to_s.strip
        options[:task]         = arg[1].to_s.strip
        options[:interval]     = arg[2].to_s.strip
        options[:date]         = arg[3]
        options[:notification] = arg
        sla.add_interval_notification options[:customer], options[:task], options[:interval], options[:date]
      else
        sla.report
      end
      exit 0
    end
    opts.on('-l', '--log', 'Log http requests') do |log|
      puts '- API logging turned on'
      options[:log] = log
    end
    opts.on_tail('-h', '-?', '--help', opts.banner) do
      puts opts
      exit 0
    end
  end
  o.parse!
  options
rescue OptionParser::ParseError => e
  puts "ERROR: #{e}\n\n"
  puts o
  exit -1
end

def monitors_do(report, config, options, &block)
  unless @monitors
    @monitors = []

    [SophosMonitor, VeeamMonitor, SkykickMonitor, CloudAllyMonitor, ZabbixMonitor, Integra365Monitor].each do |klass|
      @monitors << klass.new(report, config, options[:log])
    rescue Faraday::Error => e
      puts "** Error instantiating #{klass.name}"
      puts e
      puts e.response[:body] if e.response
    end
  end
  @monitors.each do |m|
    block.call m
  end
end

def report_tenants(report, config, options)
  puts '- report tenants'
  monitors_do(report, config, options) do |m|
    m.report_tenants
  end
end

def run_monitors(report, config, options)
	customer_alerts = {}

	monitors_do(report, config, options) do |m|
		customer_alerts = m.run(customer_alerts)
	rescue Faraday::Error => e
		puts "** Error running #{m.class.name}"
		puts e
		puts e.response[:body] if e.response
	end
	customer_alerts
end

def create_ticket(zammad_client, title, text, ticket_prio = PRIO_NORMAL, ticket_tag = nil)
  ticket = nil
  unless 'DEBUG'.eql? ENV['MONITORING']
    ticket = zammad_client.ticket.create(
      title: title,
      state: 'new',
      group: ENV['ZAMMAD_GROUP'],
      priority: ticket_prio,
      customer: ENV['ZAMMAD_CUSTOMER'],
      article: {
        content_type: 'text/plain', # or text/html, if not given test/plain is used
        body: text
      },
      tags: ticket_tag
    )
  end
  puts "Ticket created #{title}/#{ticket_prio}"
  puts text
  ticket
end

puts "Monitor v#{MONITOR_VERSION} - #{Time.now}", ''

# use environment from .env if any
Dotenv.load
config = MonitoringConfig.new
sla = MonitoringSLA.new(config)
options = get_options(config,sla)
feeds = [MonitoringDTC.new(config), MonitoringNCSC.new(config)]

File.open(FileUtil.daily_file_name('report.txt'), 'w') do |report|
  client = ZammadAPI::Client.new(
    url:          ENV['ZAMMAD_HOST'] || ENV['ZAMMAN_HOST'],
    oauth2_token: ENV['ZAMMAD_OAUTH_TOKEN']
  )
  report_tenants(report, config, options) if options[:tenants]

  customer_alerts = run_monitors(report, config, options)
  # create ticket
  last = ''
  sorted = customer_alerts.values.sort_by { |cl| cl.customer.description.upcase }
  sorted.each do |cl|
    # we have alerts

    cfg = config.by_description(cl.customer.description)
    if cfg.create_ticket
      # remove incidents reported last run(s)
      puts cfg.description unless last.eql? cfg.description
      last = cfg.description
      cfg.reported_alerts = cl.remove_reported_incidents(cfg.reported_alerts || [])
      monitoring_report = cl.report
      if monitoring_report
        _ticket = create_ticket client, "Monitoring: #{cl.name}", monitoring_report, PRIO_NORMAL, cl.source
      end
    end
  end

  a = sla.load_periodic_alerts
  a.each do |notification|
    if notification.config.create_ticket
      ticket = create_ticket client, "Monitoring: #{notification.config.description}", notification.description, PRIO_NORMAL, 'NOTIFICATION'
    end
  end
  feeds.each do |feed|
    a = feed.get_vulnerabilities_list
    a.each do |vulnerability|
      prio = if vulnerability.high_priority?
        PRIO_HIGH
      else
        PRIO_NORMAL
      end
      ticket = create_ticket(client, "Monitoring: #{vulnerability.title}", vulnerability.description, prio, feed.source)
    end
  end

  # update list of alerts
  config.compact! if options[:compact]
  config.save_config
end
