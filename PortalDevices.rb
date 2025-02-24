# frozen_string_literal: true

require 'dotenv'
require 'optparse'

require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'SophosMonitor'
require_relative 'ZabbixMonitor'
require_relative 'MonitoringModel'
require_relative 'MonitoringSLA'

# Parses command-line options for the script.
#
# @return [Hash] A hash of parsed options, including logging and company name.
# @example
#   options = parse_options
#   puts options[:log] # true if logging is enabled
def parse_options
  options = {}
  o = OptionParser.new do |opts|
    opts.banner = 'Usage: SophosDevices.rb [options]'

    opts.on('-l', '--log', 'Log http requests') do |_log|
      puts '- API logging turned on'
      options[:log] = true
    end
    opts.on('-c name', '--company name', 'Check Sophos devices for given company name') do |name|
      options[:company] = name
    end
    opts.on_tail('-h', '-?', '--help', opts.banner) do
      puts opts
      exit 0
    end
  end
  o.parse!
  unless options[:company]
    puts o
    exit 0
  end
  options
end

# Reports the types and counts of devices for a given company.
#
# @param company [Object] The company object containing device information.
# @return [void]
def report(company)
  puts company.name

  types = Hash.new(0)
  company.endpoints.each_value do |e|
    types[e.type] += 1
  end

  types.each_key do |k|
    puts "- #{k} = #{types[k]}"
  end
end

# Filters tenants by company name.
#
# @param mon [Object] The monitor object containing tenants.
# @param name [String] The company name to filter by.
# @return [Array<Object>] A list of tenants matching the company name.
def filter(mon, name)
  mon.tenants.select { |t| t.name.downcase[name] }
end

# Main execution starts here.
Dotenv.load

puts "Portal Devices 1.0 - Report number of devices from Sophos and Zabbix portals\n\n"

config = MonitoringConfig.new

options = parse_options
log = File.open('portal_devices.log', 'w')
sm = SophosMonitor.new(log, config, options[:log])
zm = ZabbixMonitor.new(log, config, options[:log])
company = options[:company].downcase

companies = []
companies += filter(sm, company)
companies += filter(zm, company)

if companies.count.positive?
  companies.each do |company|
    report company
  end
else
  puts "* Company not found '#{options[:company]}'"
end
