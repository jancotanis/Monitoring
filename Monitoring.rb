require "dotenv"
require "optparse"
require 'zammad_api'
require_relative "utils"
require_relative "MonitoringConfig"
require_relative "SophosMonitor"
require_relative "VeeamMonitor"
require_relative "SkykickMonitor"
require_relative "CloudAllyMonitor"
require_relative "MonitoringModel"

def get_options config
	options = {}
	o=OptionParser.new do |opts|
		opts.banner = "Usage: Monitor.rb [options]"

		opts.on("-s", "--sla", "Report customer SLAs") do |a|
			config.report
			exit -1
		end
	#	opts.on("-r", "--reload", "Reload cached files") do |a|
	#		options[:reload] = a
	#	end
		opts.on("-l", "--log", "Log http requests") do |log|
			options[:log] = log
		end
		opts.on_tail("-h", "-?", "--help", opts.banner) do
			puts opts
			exit -1
		end
	end
	o.parse!
	options
end

def run_monitors( report, config, options )
	customer_alerts  = {}
	monitors = [SophosMonitor, VeeamMonitor, SkykickMonitor, CloudAllyMonitor]
	monitors.each do |klass|
		m = klass.new( report, config, options[:log] )
		customer_alerts = m.run( customer_alerts )
	rescue Faraday::Error => e
		puts "** Error running #{klass.name}"
		puts e
		puts e.response[:body] if e.response
	end
	customer_alerts
end

puts "Monitor v0.9 - #{Time.now}"

# use environment from .env if any
Dotenv.load
config = MonitoringConfig.new
options = get_options config

File.open( FileUtil.daily_file_name( "report.txt" ), "w") do |report|
	client = ZammadAPI::Client.new(
		url:			ENV["ZAMMAN_HOST"],
		oauth2_token:	ENV["ZAMMAD_OAUTH_TOKEN"]
	)

	customer_alerts  = run_monitors( report, config, options )
	# create ticket
	customer_alerts.each do |id, cl|
		# we have alerts

		cfg = config.by_description(cl.customer.description)
		if cfg.create_ticket
			# remove incidents reported last run(s)
			puts cfg.description
			cfg.reported_alerts = cl.remove_reported_incidents( cfg.reported_alerts || [] )
			monitoring_report = cl.report
			if monitoring_report
				puts "Ticket created for #{cl.name}"
				puts monitoring_report
				ticket = client.ticket.create(
					title: "Monitoring: #{cl.name}",
					state: 'new',
					group: ENV['ZAMMAD_GROUP'],
					priority: '2 normal',
					customer: ENV['ZAMMAD_CUSTOMER'],
					article: {
						content_type: 'text/plain', # or text/html, if not given test/plain is used
						body: monitoring_report
					}
				)
			end
		end
	end
	# update list of alerts
	config.save_config
end
