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
MonitoringEndpoint = Struct.new(:id, :type, :hostname, :tenant, :status, :raw_data, :alerts, :incident_alerts) do
  # Initializes the MonitoringEndpoint, ensuring alerts and incident_alerts are arrays.
  #
  # @param [Array] args The arguments to initialize the struct.
  def initialize(*)
    super
    self.alerts ||= []
    self.incident_alerts ||= []
  end

  # Clears all alerts for the endpoint.
  #
  # @return [void]
  def clear_alerts
    self.alerts = []
    self.incident_alerts = []
  end

  # Returns a string representation of the endpoint.
  #
  # @return [String] The string representation in the format "type hostname".
  def to_s
    "#{type} #{hostname}"
  end
end

MonitoringIncident = Struct.new(:source, :device, :start_time, :end_time, :alert) do
  def incident_id
    "#{source}-#{alert.id}"
  end

  def time_to_s
    if start_time.eql? end_time
      start_time.to_s
    else
      "#{start_time} - #{end_time}"
    end
  end

  def endpoint_to_s
    to_s
  end

  def to_s
    "  #{time_to_s}: #{source} #{alert.severity} alert\n" \
      "   Description: #{alert.description}\n"
  end
end

CustomerAlerts = Struct.new(:name, :alerts, :devices) do
  attr_accessor :customer, :source

  def initialize(*)
    super
    @source = 'Unknown'
    self.alerts ||= []
    # default entries have empty hash
    self.devices ||= Hash.new { |hsh, key| hsh[key] = {} }
  end

  def add_incident(device, alert, klass)
    # contact alerts for same type together to get start end times
    # TODO: not all systems have alert type
    alert_type = alert.property('type')
    device_alerts = devices[alert.endpoint_id]
    if device_alerts[alert_type]
      # update end date
      incident = device_alerts[alert_type]
      incident.end_time = alert.created
    else
      instance = klass.new(device, alert.created, alert.created, alert)
      device_alerts[alert_type] = instance
      @source = instance.source
    end
  end

  def report
    if devices.count.positive?
      rpt = "Klant: #{name}\n"
      devices.each do |device_id, incidents|
        endpoint = incidents.values.first.endpoint_to_s
        rpt += "- #{endpoint} (#{device_id})\n"
        incidents.each_value do |incident|
          rpt += "#{incident}\n"
        end
      end
    else
      rpt = nil
    end
    rpt
  end

  def remove_reported_incidents(reported_alerts)
    orig = reported_alerts
    count = 0
    source = ''

    devices.each do |device_id, incidents|
      orig += incidents.values.map { |i| "#{i.source}-#{i.alert.id}" }
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

class AbstractMonitor
  attr_reader :source

  def initialize(source, client, report, config, log)
    @source = source
    @client = client
    @report = report
    @config = config
    @log = log
    @all_alerts = {}
    @tenants = @client.tenants.sort_by { |t| t.description.upcase }
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
  def monitor_tenant?(cfg)
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
