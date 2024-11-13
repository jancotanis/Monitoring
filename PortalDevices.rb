require "dotenv"
require 'optparse'

require_relative "utils"
require_relative "MonitoringConfig"
require_relative "SophosMonitor"
require_relative "ZabbixMonitor"
require_relative "MonitoringModel"
require_relative "MonitoringSLA"

def get_options
	options = {}
	o=OptionParser.new do |opts|
		opts.banner = "Usage: SophosDevices.rb [options]"

		opts.on("-l", "--log", "Log http requests") do |log|
			puts "- API logging turned on"
			options[:log] = true
		end
		opts.on("-c name", "--company name", "Check Sophos devices for given company name'") do |name|
			options[:company] = name
		end
		opts.on_tail("-h", "-?", "--help", opts.banner) do
			puts opts
			exit 0
		end
	end
	o.parse!
    if options[:company].nil?
      puts o
      exit 0
    end
	options
end

def report company
  puts company.name

  types = Hash.new(0)
  company.endpoints.values.each do |e|
    types[e.type] += 1 
  end

  types.keys.each do |k|
    puts "- #{k} = #{types[k]}"
  end
end

def filter mon, name
  mon.tenants.select{ |t| t.name.downcase[name] }
end

Dotenv.load

puts "Portal Devices 1.0 - Report number of devices from Sophos and Zabbix portals\n\n"

config = MonitoringConfig.new

options = get_options()
sm = SophosMonitor.new( File.open('sophos.log','w'), config, options[:log] )
zm = ZabbixMonitor.new( File.open('zabbix.log','w'), config, options[:log] )
company = options[:company].downcase

companies = []
companies += filter(sm, company)
companies += filter(zm, company)

if companies.count > 0
  companies.each do |company|
    report company
  end
else
  puts "* Company not found '#{options[:company]}'"
end
