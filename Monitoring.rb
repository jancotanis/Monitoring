require "dotenv"
require "optparse"
require 'zammad_api'
require_relative "utils"
require_relative "MonitoringConfig"
require_relative "SophosMonitor"
require_relative "VeeamMonitor"
require_relative "SkykickMonitor"
require_relative "CloudAllyMonitor"
require_relative "ZabbixMonitor"
require_relative "MonitoringModel"
require_relative "MonitoringSLA"
require_relative "MonitoringDTC"

def file_age(name)
  (Time.now - File.ctime(name))/(24*3600)
end
def garbage_collect days
	days = 90 unless days
	puts "- removing log files older #{days.to_i} days"
	Dir.glob( ["*.json", "*.txt","*.yml", "*.log"] ).each do |filename|
		if file_age(filename) > days
			puts "  " + filename
			File.delete( filename ) 
		end
	end
end

def get_options config, sla
	options = {}
	o=OptionParser.new do |opts|
		opts.banner = "Usage: Monitor.rb [options]"

		opts.on("-s", "--sla", "Report customer SLAs") do |a|
			config.report
			exit 0
		end
		opts.on("-t", "--tenants", "Report all tenants to json") do |a|
			options[:tenants] = a
		end
		opts.on("-c", "--compact", "Compact config file based on tenants") do |a|
			puts "- compacting configuration is on"
			options[:compact] = a
		end
		opts.on("-g[N]", "--garbagecollect[=N]", Float, "Remove all files older than N days, default is 90 days") do |a|
			garbage_collect a
		end
	#	opts.on("-r", "--reload", "Reload cached files") do |a|
	#		options[:reload] = a
	#	end
		opts.on("-n customer,task,interval[,date]", "--notification customer,task,interval[,date]", Array, "Add customer notification") do |a|
			options[:customer]	= a[0]
			options[:task]		= a[1]
			options[:interval]	= a[2]
			options[:date]		= a[3]
			options[:notification] = a
			sla.add_interval_notification a[0], a[1], a[2], a[3]
			exit 0
		end
		opts.on("-l", "--log", "Log http requests") do |log|
			puts "- API logging turned on"
			options[:log] = log
		end
		opts.on_tail("-h", "-?", "--help", opts.banner) do
			puts opts
			exit 0
		end
	end
	o.parse!
	options
end

def monitors_do report, config, options, &block
	if !@monitors
		@monitors = []
		
		[SophosMonitor, VeeamMonitor, SkykickMonitor, CloudAllyMonitor, ZabbixMonitor] .each do |klass|
			@monitors << klass.new( report, config, options[:log] )
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
	puts "- report tenants"
	monitors_do(report, config, options) do |m|
		m.report_tenants
	end
end

def run_monitors( report, config, options )
	customer_alerts  = {}

	monitors_do(report, config, options) do |m|
		customer_alerts = m.run( customer_alerts )
	rescue Faraday::Error => e
		puts "** Error running #{m.class.name}"
		puts e
		puts e.response[:body] if e.response
	end
	customer_alerts
end

def create_ticket zammad_client, title, text
	ticket = nil
	if !"DEBUG".eql? ENV["MONITORING"]
		ticket = zammad_client.ticket.create(
			title: title,
			state: 'new',
			group: ENV['ZAMMAD_GROUP'],
			priority: '2 normal',
			customer: ENV['ZAMMAD_CUSTOMER'],
			article: {
				content_type: 'text/plain', # or text/html, if not given test/plain is used
				body: text
			}
		)
	end
	puts "Ticket created #{title}"
	puts text
	ticket
end

puts "Monitor v1.1.0 - #{Time.now}"

# use environment from .env if any
Dotenv.load
config = MonitoringConfig.new
sla = MonitoringSLA.new( config )
dtc = MonitoringDTC.new( config )
options = get_options config, sla

File.open( FileUtil.daily_file_name( "report.txt" ), "w") do |report|
	client = ZammadAPI::Client.new(
		url:			ENV["ZAMMAN_HOST"],
		oauth2_token:	ENV["ZAMMAD_OAUTH_TOKEN"]
	)
	report_tenants( report, config, options ) if options[:tenants]

	customer_alerts  = run_monitors( report, config, options )
	# create ticket
	last = ""
	sorted = customer_alerts.values.sort_by{ |cl| cl.customer.description.upcase }
	sorted.each do |cl|
		# we have alerts

		cfg = config.by_description(cl.customer.description)
		if cfg.create_ticket
			# remove incidents reported last run(s)
			puts cfg.description unless last.eql? cfg.description
			last = cfg.description
			cfg.reported_alerts = cl.remove_reported_incidents( cfg.reported_alerts || [] )
			monitoring_report = cl.report
			if monitoring_report
				ticket = create_ticket client, "Monitoring: #{cl.name}", monitoring_report
			end
		end
	end

	a = sla.get_periodic_alerts
	a.each do |notification|
		if notification.config.create_ticket
			ticket = create_ticket client, "Monitoring: #{notification.config.description}", notification.description
		end
	end

	a = dtc.get_vulnerabilities_list
	a.each do |vulnerability|
		ticket = create_ticket client, "Monitoring: #{vulnerability.title}", vulnerability.description
	end
	
	# update list of alerts
	config.compact! if options[:compact]
	config.save_config
end
