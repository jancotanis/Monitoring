# frozen_string_literal: true

#
# 1.0	Initial version of monitoring coas saas vendor portals
#
HSYNC_VERSION = '1.0.3'

require 'dotenv/load'
require 'optparse'
require 'hudu'
require_relative 'hudu_matcher'
require_relative 'hudu_dashboard'
require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'MonitoringSLA'

HUDU_LOGGER = 'hudu-sync.log'
LAYOUT = 'Company Dashboard'

# SyncServices handles the synchronization between a portal and HUDU,
# ensuring the proper alignment of services and assets. It manages
# creating, updating, and syncing layout and service configurations.
class SyncServices
  # Initializes a new SyncServices object with the required parameters.
  #
  # @param client [Object] The client object to interact with the asset system.
  # @param matcher [Object] The matcher responsible for determining asset matches.
  # @param refresh [Boolean] A flag to determine whether to refresh the data.
  def initialize(client, matcher, refresh)
    @client  = client
    @matcher = matcher
    @refresh = refresh
    @dash    = DashBuilder.new(@client)
    @layout  = @client.asset_layouts.select { |al| LAYOUT.eql? al.name }.first
    @assets  = @client.assets({ asset_layout_id: @layout.id })
    @assets_by_id = @assets.to_h { |o| [o.company_id, o] }
  rescue Hudu::HuduError => e
    puts "** Error loading layout #{LAYOUT}, aborting sync: #{e}"
  end

  # Synchronizes the services and layout configurations for each matched asset.
  #
  # Iterates over each match between the HUDU and portal services, checking if an asset
  # exists. If an asset is found, it updates the layout; otherwise, it creates a new layout.
  def sync
    # get all assets/services for the services layout
    @matcher.matches.each do |hudu, portal|
      # for all portal matches, do we have a services layout
      if (asset = @assets_by_id[hudu.id]) # assignement
        update_layout(hudu, portal, asset)
      else
        create_layout(hudu, portal)
      end
    end
  end

  # Updates the dashboard by creating a dash for each asset in the layout.
  def update_dashes
    @assets.each do |asset|
      puts asset.company_name
      @dash.create_dash_from_asset(asset)
    end
  end

  private

  # Updates the asset layout based on the services and portal information.
  #
  # @param hudu [Object] The HUDU object for the asset.
  # @param portal [Object] The portal object for the service.
  # @param asset [Object] The asset to be updated.
  def update_layout(hudu, portal, asset)
    asset_layout = AssetLayout.create(asset)
    return unless update_services(asset_layout.fields, portal) || @refresh

    puts "Updating #{hudu.name}"
    asset.fields = asset_layout.custom_fields
    @client.update_company_asset(asset)
    @dash.create_dash_from_asset(asset)
  end

  # Creates a new asset layout based on the provided HUDU and portal.
  #
  # @param hudu [Object] The HUDU object for the asset.
  # @param portal [Object] The portal object for the service.
  def create_layout(hudu, portal)
    # no asset asigned so create one
    asset_layout = AssetLayout.create(@layout, true)
    puts "Creating #{hudu.name}"

    update_services(asset_layout.fields, portal)
    puts "+ creating layout for #{@layout.name}..."

    asset = @client.create_company_asset(hudu.id, @layout, asset_layout.custom_fields)
    @dash.create_dash_from_asset(asset)
  end

  # Updates the service settings on the provided asset fields.
  #
  # @param fields [Array] The fields of the asset to be updated.
  # @param portal [Object] The portal object containing service settings.
  #
  # @return [Boolean] Returns true if any changes were made, otherwise false.
  def update_services(fields, portal)
    changes = false
    # source = serice assigned to asset
    fields.each do |field|
      # only for known portal services
      Services::KNOWN_SERVICES.each do |service|
        test = Services::TITLE_TEST[service]
        next unless field.label.downcase[test]

        set_value = set_new_value?(service, portal)
        changes ||= has_changes?(service, field.value, set_value)
        field.value = set_value

        # This overwrites existing notes...
        changes ||= update_field_note(field, service, portal, set_value)
        field.url = Services.url(service) if set_value || field.url.to_s.empty?
      end
    end
    changes
  end

  # New method for updating the field note
  def update_field_note(field, service, portal, set_value)
    if set_value
      note = field.note
      field.note = get_note(service, portal)
      !note.to_s.eql?(field.note) # returns true if there was a change in the note
    else
      field.note = '-'
      false
    end
  end

  # Checks if the value has changed between the original and the new value.
  #
  # @param original_value [Object] The original value.
  # @param new_value [Object] The new value.
  #
  # @return [Boolean] True if there are changes, false otherwise.
  def has_changes?(service, original_value, new_value)
    return false if original_value == new_value

    puts "- #{service} service turning #{onoff(new_value)}, was #{onoff(original_value)}"
    true
  end

  # Determines the new value for a given service based on the portal's configuration.
  #
  # @param service [Symbol] The service to check.
  # @param portal [Object] The portal object to fetch settings from.
  #
  # @return [Boolean] The new value for the service setting.
  def set_new_value?(service, portal)
    service.eql?(Services::DTC) ? (portal.monitor_dtc == true) : portal.source.include?(service)
  end

  # Generates the note based on the service, portal, and monitoring status.
  #
  # @param service [Symbol] The service to generate the note for.
  # @param portal [Object] The portal object to determine monitoring.
  #
  # @return [String] The generated note text.
  def get_note(service, portal)
    if monitoring_service?(service, portal) && portal.create_ticket
      Services::SLA_TEXT
    else
      "Customer has #{service}; no SLA"
    end
  end

  # Determines if a service is being monitored based on the portal configuration.
  #
  # @param service [Symbol] The service to check.
  # @param portal [Object] The portal object containing monitoring configuration.
  #
  # @return [Boolean] Whether the service is monitored.
  def monitoring_service?(service, portal)
    # return case value
    case service
    when Services::SOPHOS
      portal.monitor_endpoints
    when Services::ZABBIX
      portal.monitor_connectivity
    when Services::DTC
      portal.monitor_dtc
    else
      # Services::VEEAM, Services::INTEGRA365, ...
      portal.monitor_backup
    end
  end

  # Converts a boolean value into its string equivalent, "on" or "off".
  #
  # @param value [Boolean] The boolean value to convert.
  #
  # @return [String] The string representation of the boolean value.
  def onoff(value)
    value ? 'on' : 'off'
  end
end

def get_options(_config)
  options = {}
  o = OptionParser.new do |opts|
    opts.banner = 'Usage: HuduSync.rb [options]'

    opts.on('-l', '--log', 'Log http requests') do |_arg|
      puts '- API logging turned on'
      options[:log] = Logger.new(HUDU_LOGGER)
    end
    opts.on('-c', '--clean', "Cleanup old magic dashed 'comp - service'") do |_arg|
      puts '- Cleaning dashes'
      options[:clean] = true
    end
    opts.on('-r', '--refresh', 'Recreate all dashes') do |_arg|
      puts '- Refresh dashes'
      options[:refresh] = true
    end
    opts.on_tail('-h', '-?', '--help', opts.banner) do
      puts opts
      exit 0
    end
  end
  o.parse!
  options
end

def dash_cleanup(client, companies)
  matches = []
  dashboards = client.magic_dashes
  Services::TITLE_TEST.each_value do |test|
    m = dashboards.select { |dash| dash.title.downcase.include? test }
    m.each do |dashboard|
      matches = companies.select { |company| dashboard.title.include?(company[:description]) }
      if matches.count.positive?
        puts dashboard.title
        client.delete(client.api_url("magic_dash/#{dashboard.id}"))
      end
    end
  end
end

def create_hudu_client(log)
  Hudu.configure do |config|
    config.endpoint = ENV.fetch('HUDU_API_HOST').downcase
    config.api_key = ENV.fetch('HUDU_API_KEY')
    config.page_size = 500
    config.logger = log if log
  end
  client = Hudu.client
  client.login
  client
end

puts "HuduSync v#{HSYNC_VERSION} - #{Time.now}"

config = MonitoringConfig.new
options = get_options(config)
client = create_hudu_client(options[:log])

if options[:clean]
  puts 'Cleanup old dashes'
  dash_cleanup(client, config.entries)
else
  puts 'Loading HUDU companies...'
  companies = client.companies

  FileUtil.write_file('hudu-companies.txt', companies.map(&:name))
  puts "- Found #{companies.count} companies"
  puts "- Found #{config.entries.count} portal entries"

  puts 'Matching HUDU with portal companies...'
  m = Matcher.new(companies, config)
  puts 'Synchronize assets...'
  s = SyncServices.new(client, m, options[:refresh])
  s.sync
end

puts 'ready...'
