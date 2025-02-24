# frozen_string_literal: true

#
# 1.0	Initial version of monitoring coas saas vendor portals
#
HSYNC_VERSION = '1.0.1'

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

class Matcher
  attr_reader :matches, :nonmatches

  def initialize(hudu_companies, monitoring_config)
    @hudu = hudu_companies
    @portal = monitoring_config
    @matches, @nonmatches = match(@hudu, @portal)
  end

  def match(hudu, monitoring)
    matches = {}
    nomatch = []
    hudu.each do |company|
      mon = monitoring.by_description(company.name)
      name = company.name.downcase
      # retry partial match ans skip 'test' company
      if !mon && !'test'.eql?(name)
        found = monitoring.entries.select { |cfg| name[cfg.description.downcase] || cfg.description.downcase[name] }
        if found.count.positive?
          mon = found.first
          puts " Partial match found #{company.name} / #{mon.description}" if mon
          puts "* Duplicate match for #{mon.description}" if mon.touched?
          mon.touch
        end
      end

      if mon
        matches[company] = mon
      else
        nomatch << company
      end
    end
    [matches, nomatch]
  end
end

LAYOUT = 'Company Dashboard'

CustomField = Struct.new(:label, :value)
LayoutField = Struct.new(:label, :value, :note, :url, :type)
AssetLayout = Struct.new(:asset, :fields) do
  def initialize(asset)
    super
    @fields = {}
  end

  def fields
    @fields.values
  end

  def self.create(asset, is_layout = false)
    a = AssetLayout.new(asset)
    asset.fields.each { |f| a.add_field(f, is_layout) }
    a
  end

  def update_asset(_asset)
    raise StandardError, 'not implemented'
  end

  def add_field(hudu_field, is_layout = false)
    split = hudu_field.label.split ':'
    label = split[0]

    field = @fields[label] || LayoutField.new(label, false, '', '')

    case split[1]
    when Actions::ENABLED
      field.value = if is_layout
                      false
                    else
                      hudu_field.value
                    end
      field.type = Actions::ENABLED
    when Actions::NOTE
      field.note = hudu_field.value unless is_layout
    when Actions::URL
      field.url = hudu_field.value unless is_layout
    end
    @fields[label] = field
  end

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

class SyncServices
  def initialize(client, matcher, refresh)
    @client  = client
    @matcher = matcher
    @refresh = refresh
    @layout  = @client.asset_layouts.select { |al| LAYOUT.eql? al.name }.first

    @assets = @client.assets({ asset_layout_id: @layout.id })
    @assets_by_id = @assets.map { |o| [o.company_id, o] }.to_h
  rescue => e
    puts "** Error loading layout #{LAYOUT}, aborting sync: #{e}"
  end

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

  def update_dashes
    @assets.each do |asset|
      puts asset.company_name
      create_dash_from_asset(asset)
    end
  end

private

  def update_layout(hudu, portal, asset)
    asset_layout = AssetLayout.create(asset)
    if update_services(asset_layout.fields, portal) || @refresh
      puts "Updating #{hudu.name}"
      asset.fields = asset_layout.custom_fields
      @client.update_company_asset(asset)
      create_dash_from_asset(asset)
    end
  end
  
  def create_layout(hudu, portal)
    # no asset asigned so create one
    asset_layout = AssetLayout.create(@layout, true)
    puts "Creating #{hudu.name}"

    update_services(asset_layout.fields, portal)
    puts "+ creating layout for #{@layout.name}..."

    asset = @client.create_company_asset(hudu.id, @layout, asset_layout.custom_fields)
    create_dash_from_asset(asset)
  end

  def create_dash_from_asset(asset)
    layout = AssetLayout.create(asset)
    layout.fields.each do |service|
      if Actions::ENABLED.eql? service.type

        if service.value && !service.value.to_s.empty?
          colour = 'success'
        else
          message = Services::NO_SERVICE_TEXT
          colour = 'grey'
        end

        if service.note && !service.note.empty?
          message = service.note
        else # do not touch the message
          message = Services::NO_SERVICE_TEXT
        end

#        if service.url && !service.url.empty?
#          url = service.url unless service.url.empty?
#        else
        url = service.url
#        end

        dash = dash_structure(service.label, asset.company_name, colour, message, url)
        @client.post(@client.api_url('magic_dash'), dash)
      end
    end
  end

  def dash_structure(label, company_name, colour, message, url)
    {
      'title' => label,
      'company_name' => company_name,
      'content_link' => url,
      'shade' => colour,
      'message' => message # efault
    }
  end

  # update HUDU service settings to reflect monitoring settings
  def update_services(fields, portal)
    changes = false
    # source = serice assigned to asset
    fields.each do |field|
      # only for known portal services
      monitoring = false
      Services::KNOWN_SERVICES.each do |service|
        set_value = portal.source.include? service
        test = Services::TITLE_TEST[service]
        case service
        when Services::SOPHOS
          monitoring = portal.monitor_endpoints
        when Services::ZABBIX
          monitoring = portal.monitor_connectivity
        when Services::VEEAM
          monitoring = portal.monitor_backup
        when Services::INTEGRA365
          monitoring = portal.monitor_backup
        when Services::DTC
          set_value = (portal.monitor_dtc == true)
          monitoring = portal.monitor_dtc
        else
          monitoring = portal.monitor_backup
        end

        if field.label.downcase[test]
          if field.value != set_value
            changes = true
            puts "- #{service} service turning #{onoff(set_value)}, was #{onoff(field.value)}"
          end
          field.value = set_value

          # This overwrites existing notes...
          if set_value
            note = field.note
            if monitoring && portal.create_ticket
              field.note = Services::SLA_TEXT
            else
              field.note = "Customer has #{service}; no SLA"
            end
            changes ||= (changes || !note.to_s.eql?(field.note))
          else
            field.note = '-'
          end
          field.url = Services.url(service) if set_value || field.url.to_s.empty?
        end
      end
    end
    changes
  end

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
    config.endpoint = ENV['HUDU_API_HOST'].downcase
    config.api_key = ENV['HUDU_API_KEY']
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
