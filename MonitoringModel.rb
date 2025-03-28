# frozen_string_literal: true

# Represents a monitoring endpoint with its details and alerts.
#
# @!attribute [rw] id
#   @return [Integer] The unique identifier of the endpoint.
# @!attribute [rw] type
#   @return [String] The type of the endpoint (e.g., server, device).
# @!attribute [rw] hostname
#   @return [String] The hostname of the endpoint.
# @!attribute [rw] tenant
#   @return [String] The tenant or company the endpoint belongs to.
# @!attribute [rw] status
#   @return [String] The current status of the endpoint (e.g., active, inactive).
# @!attribute [rw] raw_data
#   @return [Hash] The raw data associated with the endpoint.
# @!attribute [rw] alerts
#   @return [Array] A list of general alerts for the endpoint.
# @!attribute [rw] incident_alerts
#   @return [Array] A list of incident-specific alerts for the endpoint.
MonitoringEndpoint = Struct.new(:id, :type, :hostname, :tenant, :status, :raw_data, :alerts) do
  # Initializes the MonitoringEndpoint, ensuring alerts and incident_alerts are arrays.
  #
  # @param [Array] args The arguments to initialize the struct.
  def initialize(*)
    super
    self.alerts ||= []
  end

  # Clears all alerts for the endpoint.
  #
  # @return [void]
  def clear_alerts
    self.alerts = []
  end

  # Returns a string representation of the endpoint.
  #
  # @return [String] The string representation in the format "type hostname".
  def to_s
    "#{type} #{hostname}"
  end
end

# Represents a monitoring incident that occurred on a device.
#
# @!attribute [r] source
#   @return [String] The source of the incident (e.g., monitoring system name).
# @!attribute [r] device
#   @return [String] The device associated with the incident.
# @!attribute [r] start_time
#   @return [Time] The timestamp when the incident started.
# @!attribute [r] end_time
#   @return [Time] The timestamp when the incident ended.
# @!attribute [r] alert
#   @return [Object] The alert associated with the incident.
MonitoringIncident = Struct.new(:source, :device, :start_time, :end_time, :alert) do
  # Generates a unique incident ID based on the source and alert ID.
  #
  # @return [String] The unique incident identifier.
  def incident_id
    "#{source}-#{alert.id}"
  end

  # Returns a formatted string representation of the incident time.
  #
  # @return [String] The formatted time range, or a single timestamp if start and end times are the same.
  def time_to_s
    if start_time.eql? end_time
      start_time.to_s
    else
      "#{start_time} - #{end_time}"
    end
  end

  # Returns a string representation of the endpoint.
  #
  # @return [String] The string representation of the endpoint.
  def endpoint_to_s
    to_s
  end

  # Returns a human-readable string describing the incident.
  #
  # @return [String] A formatted string containing time, source, severity, and alert description.
  def to_s
    "  #{time_to_s}: #{source} #{alert.severity} alert\n" \
      "   Description: #{alert.description}\n"
  end
end

# Represents customer alerts and creates incidents grouped by device.
#
# @!attribute [rw] name
#   @return [String] The name of the customer.
# @!attribute [rw] alerts
#   @return [Array] A list of alerts for the customer.
# @!attribute [rw] devices
#   @return [Hash] A hash of devices and their associated incidents.
CustomerAlerts = Struct.new(:name, :alerts, :devices) do
  attr_accessor :customer, :source

  # Initializes the CustomerAlerts, ensuring alerts and devices are properly set.
  #
  # @param [Array] args The arguments to initialize the struct.
  def initialize(*)
    super
    @source = 'Unknown'
    self.alerts ||= []
    self.devices ||= Hash.new { |hsh, key| hsh[key] = {} }
  end

  # Adds an incident to the customer alerts.
  #
  # @param [String] device_id The ID of the device.
  # @param [Object] alert The alert object.
  # @param [Class] klass The class used to create the incident.
  # @return [void]
  def add_incident(device_id, alert, klass)
    # contact alerts for same type together to get start end times
    # TODO: not all systems have alert type
    alert_type = alert.type

    device_alerts = devices[alert.endpoint_id]
    if (incident = device_alerts[alert_type])
      # update end date & alert
      incident.end_time = alert.created
    else
      instance = klass.new(device_id, alert.created, alert.created, alert)
      device_alerts[alert_type] = instance
      @source = instance.source
    end
  end

  # Generates a report of the customer alerts.
  #
  # @return [String, nil] The report string or nil if there are no devices.
  def report
    if devices.count.positive?
      # create mutable string
      rpt = String.new "Klant: #{name}\n"
      devices.each do |device_id, incidents|
        endpoint = incidents.values.first.endpoint_to_s
        rpt << "- #{endpoint} (#{device_id})\n"
        incidents.each_value do |incident|
          rpt << "#{incident}\n"
        end
      end
    else
      rpt = nil
    end
    rpt
  end

  # Removes reported incidents from the customer alerts.
  #
  # @param [Array] reported_alerts The list of reported alerts.
  # @return [Array] The updated list of reported alerts.
  def remove_reported_incidents(reported_alerts)
    orig = reported_alerts
    count = 0
    source = ''

    devices.each do |device_id, incidents|
      orig += incidents.values.map { |incident| "#{incident.source}-#{incident.alert.id}" }
      incidents.each do |type, incident|
        # backward compatibility, check for reported alerts without prefix
        next unless reported_alerts.include?(incident.incident_id) || reported_alerts.include?(incident.alert.id)

        source = incident.source
        count += 1
        orig.delete(incident.alert.id)
        incidents.delete(type)
      end
      # remove if all incidents have been removed
      devices.delete(device_id) if incidents.count.zero?
    end
    puts "- #{count} #{source} incident(s) already reported" if count.positive?
    orig.uniq
  end
end

# Module for monitoring tenant endpoints and managing alerts.
#
# This module provides functionality to interact with a tenant's endpoints,
# specifically to clear any active alerts.
#
# @example Usage
#   tenant = MonitoringTenant.new
#   tenant.clear_endpoint_alerts
#   puts tenant.description
#
module MonitoringTenant
  # Clears alerts for all endpoints associated with the tenant.
  #
  # This method iterates over all available endpoints and calls `clear_alerts`
  # on each one. If there are no endpoints, the method does nothing.
  #
  # @return [void]
  def clear_endpoint_alerts
    endpoints&.each_value(&:clear_alerts)
  end

  # Alias for `name`, returning the name of the tenant.
  #
  # @return [String] the name of the tenant
  def description
    name
  end
end

# Module: MonitoringAlert
# This module provides defaut methods for monitoring alerts.
#
# Usage:
#   class Alert
#     include MonitoringAlert
#
#     def description
#       "Critical Alert"
#     end
#   end
#
#   alert = Alert.new
#   puts alert.type  # Output: "Critical Alert"
#
module MonitoringAlert
  # Returns the `description` of the object as `type`. type is used to summarize similar events
  #
  # @return [String] the description of the alert.
  def type
    description
  end
end

##
# Abstract class for monitorign portals and processing all tenants/alerts
class AbstractMonitor
  attr_reader :source

  def initialize(source, client, report, config, log)
    @source = source
    @client = client
    @report = report
    @config = config
    @log = log
    @all_alerts = {}
    @tenants = @client.tenants.sort_by { |tnt| tnt.description.upcase }
    @config.load_config(source, @tenants)
  end

  # Runs the monitor to collect and process alerts.
  #
  # Iterates through all tenants, retrieves backup alerts, and logs incidents.
  #
  # @param all_alerts [Hash] A hash to store collected alerts, organized by customer ID.
  # @return [Hash] The updated `all_alerts` hash with collected incidents.
  #
  def run(all_alerts)
    collect_data

    @tenants.each do |customer|
      process_customer_alerts(customer, all_alerts)
    end

    persist_alerts(all_alerts)
    all_alerts
  end

  def report_tenants
    FileUtil.write_file("#{source.downcase}-tenants.json", @client.tenants.to_json)
  end

  protected

  # Collect all required data to monitor
  #
  def collect_data
    raise NotImplementedError, 'You must implement this method'
  end

  # Check if tenant config should be monitored
  #
  def monitor_tenant?(_cfg)
    raise NotImplementedError, 'You must implement this method'
  end

  # Processes active tenants by clearing their endpoint alerts and executing a monitoring block.
  #
  # This method iterates through all tenants, clears their endpoint alerts, retrieves
  # their configuration, and conditionally yields them to a provided block if they meet
  # monitoring criteria.
  #
  # @yield [customer, cfg] Yields the tenant and its configuration if it meets monitoring conditions.
  # @yieldparam customer [Object] The tenant being processed.
  # @yieldparam cfg [Object] The configuration associated with the tenant.
  #
  # @note A slight delay (0.05 seconds) is introduced between iterations to throttle API calls.
  #
  # @return [void]
  def process_active_tenants
    @tenants.each do |customer|
      customer.clear_endpoint_alerts
      cfg = @config.by_description(customer.description)

      yield(customer, cfg) if monitor_tenant?(cfg)
      # throttle api
      sleep(0.05)
    end
  end

  # Collect all alerts
  #
  def collect_alerts(tenant)
    @client.alerts(tenant.id)
  end

  # Processes alerts for a single customer and adds them to all_alerts.
  #
  # @param customer [Object] The customer object being processed.
  # @param all_alerts [Hash] The hash storing all alerts.
  #
  def process_customer_alerts(_customer, _all_alerts)
    raise NotImplementedError, 'You must implement this method'
  end

  def create_endpoint_from_alert(customer, alert)
    device_id = alert.endpoint_id
    endpoint = customer.endpoints[device_id]
    unless endpoint
      # create endpoint from alert
      customer.endpoints[device_id] = endpoint = alert.create_endpoint
    end
    endpoint
  end

  # Persists all collected alerts to a JSON file.
  #
  # @param all_alerts [Hash] The hash of all collected alerts.
  #
  def persist_alerts(all_alerts)
    FileUtil.write_file(FileUtil.daily_file_name("#{@source.downcase}-alerts.json"), all_alerts.to_json)
  end
end
