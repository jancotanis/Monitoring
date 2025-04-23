# frozen_string_literal: true

require_relative 'utils'

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
    KNOWN_SERVICES.any? { |s| s.casecmp?(service) }
  end

  def self.url(service)
    SERVICE_URL[service]
  end
end

# Represents a custom field
CustomField = Struct.new(:label, :value)

# Represents a layout field with additional properties
LayoutField = Struct.new(:label, :value, :note, :url, :type)

# Represents an asset layout which contains fields associated with an asset.
# Provides methods for managing fields, adding new fields, and updating them.
AssetLayout = Struct.new(:asset) do
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
    label, action = hudu_field.label.split ':'
    field = @fields[label] || LayoutField.new(label, false, '', '')

    return if is_layout && action != Actions::ENABLED

    case action
    when Actions::ENABLED
      field.value = hudu_field.value unless is_layout
      field.type = Actions::ENABLED
    when Actions::NOTE
      field.note = hudu_field.value
    when Actions::URL
      field.url = hudu_field.value
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

      colour = service.value ? 'success' : 'gray'
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
