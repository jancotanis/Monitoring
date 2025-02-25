# frozen_string_literal: true

#
# 1.0	Initial version of monitoring coas saas vendor portals
#
HSYNC_VERSION = '1.0.2'

require 'dotenv/load'
require 'optparse'
require 'hudu'
require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'MonitoringSLA'

HUDU_LOGGER = 'hudu-sync.log'

# Defines a set of enumerated constants for specific actions.
#
# The `Actions` class inherits from `Enum` and defines a list of action-related constants.
# These constants represent different types of actions, such as `ENABLED`, `NOTE`, and `URL`.
#
# @example Accessing defined constants:
#   Actions::ENABLED  # => "ENABLED"
#   Actions::NOTE     # => "NOTE"
#   Actions::URL      # => "URL"
#
# @example Accessing all action constants:
#   Actions::ACTIONS  # => ["ENABLED", "NOTE", "URL"]
class Actions < Enum
  enum %w[ENABLED NOTE URL]
  ACTIONS = constants.inject([]) { |result, const| result << const_get(const) }
end

# Defines a set of enumerated constants for various services and provides utility methods to interact with them.
#
# The `Services` class inherits from `Enum` and dynamically defines constants for several known services.
# Additionally, it provides methods to check if a service is known and retrieve associated URLs for services.
#
# @example Accessing defined constants:
#   Services::CLOUDALLY  # => "CloudAlly"
#   Services::SKYKICK    # => "Skykick"
#   Services::DTC        # => "DTC"
#
# @example Accessing all known services:
#   Services::KNOWN_SERVICES  # => ["CloudAlly", "Skykick", "Sophos", "Veeam", "Integra365", "Zabbix", "DTC"]
#
# @example Retrieving a service URL:
#   Services.url(Services::CLOUDALLY)  # => "https://partners.cloudally.com/"
#
# @example Checking if a service is known:
#   Services.known_service?("Skykick")  # => true
#
class Services < Enum
  enum %w[CloudAlly Skykick Sophos Veeam Integra365 Zabbix DTC]
  # No CONST before this line
  KNOWN_SERVICES = constants.inject([]) { |result, const| result << const_get(const) }

  NO_SERVICE_TEXT = '-'
  SLA_TEXT        = 'Monitoring SLA'
  SERVICE_URL = {
    CLOUDALLY => 'https://partners.cloudally.com/',
    SKYKICK => 'https://manage.skykick.com/',
    SOPHOS => 'https://cloud.sophos.com/manage/partner',
    VEEAM => ENV.fetch('VEEAM_API_HOST'),
    INTEGRA365 => 'https://office365.integra-bcs.nl/',
    ZABBIX => ENV.fetch('ZABBIX_API_HOST'),
    DTC => 'https://www.digitaltrustcenter.nl/cyberalerts'
  }.freeze
  TITLE_TEST = {
    CLOUDALLY => CLOUDALLY.downcase,
    SKYKICK => SKYKICK.downcase,
    SOPHOS => SOPHOS.downcase,
    VEEAM => 'integra cloud',
    INTEGRA365 => 'integra office365',
    ZABBIX => ZABBIX.downcase,
    DTC => 'digital trust center'
  }.freeze

  def self.known_service?(service)
    KNOWN_SERVICES.include? service.downcase
  end

  def self.url(service)
    SERVICE_URL[service]
  end
end

# Matcher is responsible for matching companies between Hudu and a monitoring configuration.
#
# This class attempts to find exact or partial matches between companies in the Hudu system
# and their corresponding monitoring configurations.
#
# @example Usage
#   matcher = Matcher.new(hudu_companies, monitoring_config)
#   puts matcher.matches
#   puts matcher.nonmatches
#
class Matcher
  attr_reader :matches, :nonmatches

  # Initializes the Matcher with Hudu companies and monitoring configuration.
  #
  # It automatically attempts to match companies upon initialization.
  #
  # @param hudu_companies [Array<Object>] A list of companies from Hudu.
  # @param monitoring_config [Object] The monitoring configuration containing company entries.
  def initialize(hudu_companies, monitoring_config)
    @hudu = hudu_companies
    @portal = monitoring_config
    @matches, @nonmatches = match(@hudu, @portal)
  end

  private

  # Matches Hudu companies with monitoring configuration entries.
  #
  # This method first attempts an exact match by description. If an exact match is not found,
  # it performs a partial match unless the company is named "test". If multiple matches are found,
  # it selects the first and logs a warning about duplicates.
  #
  # @param hudu [Array<Object>] A list of companies from Hudu.
  # @param monitoring [Object] The monitoring configuration containing company entries.
  #
  # @return [Array<Hash, Array>] A tuple containing matched companies as a hash
  #   (`{ company => monitoring_entry }`) and a list of non-matching companies.
  def match(hudu, monitoring)
    matches = {}
    nonmatches = []
    hudu.each do |company|
      mon = monitoring.by_description(company.name)
      name = company.name.downcase

      # No exact match found and skip 'test' company
      if mon.nil? && !'test'.eql?(name)
        if (found = partial_match?(monitoring.entries, name)).any?
          mon = found.first
          puts " Partial match found: #{company.name} / #{mon.description}" if mon
          puts "* Duplicate match for #{mon.description}" if mon.touched?
          mon.touch
        end
      end

      if mon
        matches[company] = mon
      else
        nonmatches << company
      end
    end
    [matches, nonmatches]
  end

  # Checks if a given company name partially matches any company descriptions in the list.
  #
  # This method performs a case-insensitive check to see if the `company_name` is a substring
  # of any company's description or vice versa.
  #
  # @param companies [Array] An array of objects that must respond to `description`.
  # @param company_name [String] The company name to check for partial matches.
  # @return [Boolean] `true` if a partial match is found, otherwise `false`.
  #
  # @example
  #   companies = [OpenStruct.new(description: "TechCorp"), OpenStruct.new(description: "InnoSoft")]
  #   partial_match?(companies, "tech")           #=> true
  #   partial_match?(companies, "innosoftware")   #=> true
  #   partial_match?(companies, "apple")          #=> false
  #
  def partial_match?(companies, company_name)
    companies.select do |company|
      name = company.description.downcase
      company_name.include?(name) || name.include?(company_name)
    end
  end
end

LAYOUT = 'Company Dashboard'

# Represents a custom field
CustomField = Struct.new(:label, :value)
# Represents a layout field with additional properties
LayoutField = Struct.new(:label, :value, :note, :url, :type)

# Represents an asset layout which contains fields associated with an asset.
# Provides methods for managing fields, adding new fields, and updating them.
AssetLayout = Struct.new(:asset, :fields) do
  # Initializes a new AssetLayout instance.
  # @param asset [Object] The asset associated with this layout.
  def initialize(asset)
    super
    @fields = {}
  end

  # Returns an array of all the fields contained within the asset layout.
  # @return [Array<LayoutField>] The list of all fields.
  def fields
    @fields.values
  end

  # Creates a new AssetLayout object and populates its fields based on the asset provided.
  # @param asset [Object] The asset to be associated with the layout.
  # @param is_layout [Boolean] Flag indicating whether it's a layout (default: false).
  # @return [AssetLayout] The created AssetLayout object.

  def self.create(asset, is_layout = false)
    a = AssetLayout.new(asset)
    asset.fields.each { |f| a.add_field(f, is_layout) }
    a
  end

  # Placeholder method to update an asset (not yet implemented).
  # @param _asset [Object] The asset to be updated.
  # @raise [StandardError] Always raises an exception since this method is not implemented.
  def update_asset(_asset)
    raise StandardError, 'not implemented'
  end

  # Adds a new field or updates an existing field within the layout.
  # @param hudu_field [Object] The field to be added or updated.
  # @param is_layout [Boolean] Flag indicating whether the field is a layout (default: false).
  def add_field(hudu_field, is_layout = false)
    split = hudu_field.label.split ':'
    label = split[0]

    field = @fields[label] || LayoutField.new(label, false, '', '')

    case split[1]
    when Actions::ENABLED
      field.value = is_layout ? false : hudu_field.value
      field.type = Actions::ENABLED
    when Actions::NOTE
      field.note = hudu_field.value unless is_layout
    when Actions::URL
      field.url = hudu_field.value unless is_layout
    end
    @fields[label] = field
  end

  # Returns an array of CustomField instances for all fields in the layout.
  # @return [Array<CustomField>] A list of custom fields with label and respective values.
  def custom_fields
    custom = []
    fields.each do |f|
      custom << CustomField.new("#{f.label}:#{Actions::ENABLED}", f.value)
      custom << CustomField.new("#{f.label}:#{Actions::NOTE}", f.note)
      custom << CustomField.new("#{f.label}:#{Actions::URL}", f.url)
    end
    custom
  end
end


# DashBuilder is responsible for creating dashboard entries from assets.
#
# This class processes an asset's layout, iterates through its fields, and sends
# the relevant dashboard data to a client.
#
# @example Usage
#   client = APIClient.new
#   dash_builder = DashBuilder.new(client)
#   dash_builder.create_dash_from_asset(asset)
#
class DashBuilder
  # Initializes the DashBuilder with a client instance.
  #
  # @param client [Object] The API client used to send dashboard data.
  def initialize(client)
    @client = client
  end

  # Creates a dashboard entry from the given asset.
  #
  # This method retrieves the asset layout, iterates over its fields, and posts
  # an entry for each field that has an enabled action.
  #
  # @param asset [Object] The asset containing layout and service fields.
  # @return [void]
  def create_dash_from_asset(asset)
    layout = AssetLayout.create(asset)

    layout.fields.each do |service|
      next unless Actions::ENABLED.eql?(service.type)

      colour = service.value.to_s.empty? ? 'grey' : 'success'
      message = service.note.to_s.empty? ? Services::NO_SERVICE_TEXT : service.note

      dash = dash_structure(service.label, asset.company_name, colour, message, service.url)
      @client.post(@client.api_url('magic_dash'), dash)
    end
  end

  private

  # Builds the structured data for a dashboard entry.
  #
  # @param label [String] The label of the service.
  # @param company_name [String] The company associated with the asset.
  # @param colour [String] The display colour based on service status.
  # @param message [String] The message or note related to the service.
  # @param url [String, nil] The optional URL associated with the service.
  #
  # @return [Hash] The structured data for the dashboard.
  def dash_structure(label, company_name, colour, message, url)
    {
      'title' => label,
      'company_name' => company_name,
      'content_link' => url,
      'shade' => colour,
      'message' => message
    }
  end
end

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
        changes ||= has_changes?(field.value, set_value)
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
  def has_changes?(original_value, new_value)
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
#  companies = companies.select{|c| c.id==4}.sort_by{ |c| c.name.upcase }

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
