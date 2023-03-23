require "dotenv"
require "optparse"
require_relative "utils"
require_relative "MonitoringConfig"
require_relative "SophosMonitor"
require_relative "VeeamMonitor"
require_relative "SkykickMonitor"
require_relative 'MonitoringModel'

Dotenv.load

# helpdesk  library api
require 'zammad_api'

puts "Monitor v0.9"

config = MonitoringConfig.new
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
#	opts.on("-l", "--log", "Log http requests") do |log|
#		options[:log] = log
#	end
	opts.on_tail("-h", "-?", "--help", opts.banner) do
		puts opts
		exit -1
	end
end

begin
	o.parse!
	arg = ARGV.pop
rescue
	puts o
	exit -1
end

exit 0

customer_alerts  = {}
File.open( FileUtil.daily_file_name( "report.txt" ), "w") do |report|
	client = ZammadAPI::Client.new(
		url:			ENV["ZAMMAN_HOST"],
		oauth2_token:	ENV["ZAMMAD_OAUTH_TOKEN"]
	)
	sm = SophosMonitor.new( report, config )
	customer_alerts = sm.run( customer_alerts )
	vm = VeeamMonitor.new( report, config )
	customer_alerts = vm.run( customer_alerts )
	skm = SkykickMonitor.new( report, config )
	customer_alerts = skm.run( customer_alerts )
	# create ticket
	customer_alerts.each do |id, cl|
		# we have alerts

		cfg = sm.config.by_description(cl.customer.description)
		if cfg.create_ticket
			# remove incidents reported last run(s)
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
	sm.config.save_config
end
