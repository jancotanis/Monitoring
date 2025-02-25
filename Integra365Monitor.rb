# frozen_string_literal: true

require 'dotenv'
require 'json'

require_relative 'utils'
require_relative 'Integra365API'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

INTEGRA = 'Integra365'

# Represents an incident related to Integra backup monitoring.
#
# This class inherits from `MonitoringIncident` and is used to track
# backup-related issues for Integra devices.
#
# @example Creating a new incident
#   incident = IntegraBackupIncident.new(device, start_time, end_time, alert)
#
class IntegraBackupIncident < MonitoringIncident
  # Initializes an Integra backup incident.
  #
  # @param device [Object, nil] The device related to the incident (default: nil).
  # @param start_time [Time, nil] The start time of the incident (default: nil).
  # @param end_time [Time, nil] The end time of the incident (default: nil).
  # @param alert [Object, nil] The alert object containing incident details (default: nil).
  #
  def initialize(device = nil, start_time = nil, end_time = nil, alert = nil)
    super(INTEGRA, device, start_time, end_time, alert)
  end

  # Returns the endpoint description as a string.
  #
  # This method extracts the `jobName` property from the alert object.
  #
  # @return [String] The job name of the backup incident.
  #
  def endpoint_to_s
    alert.property('jobName').to_s
  end
end

# Monitors Integra365 backups and collects alerts.
#
# This class is responsible for monitoring backup statuses for Integra365 tenants,
# processing alerts, and organizing incidents.
#
# @example Running the monitor
#   monitor = Integra365Monitor.new(report, config, log)
#   all_alerts = {}
#   monitor.run(all_alerts)
#
class Integra365Monitor < AbstractMonitor
  # @return [Config] The configuration object for the monitor.
  attr_reader :config

  # @return [Hash] A hash storing all collected alerts.
  attr_reader :all_alerts

  # Initializes the Integra365 monitor.
  #
  # @param report [Object] The reporting object for logging alerts.
  # @param config [Config] The configuration settings.
  # @param log [Logger] Logger instance for monitoring activities.
  #
  def initialize(report, config, log)
    client = Integra365::ClientWrapper.new(ENV.fetch('INTEGRA365_USER'), ENV.fetch('INTEGRA365_PASSWORD'), log)
    super(INTEGRA, client, report, config, log)
  end

  private

  # Monitor when backup is on
  def monitor_tenant?(cfg)
    cfg.monitor_backup
  end

  # Collects and organizes data from all monitored tenants.
  #
  # Retrieves alerts for each tenant, filters out successful/running alerts,
  # and associates them with endpoints.
  #
  def collect_data
    process_active_tenants do |customer, _cfg|
      customer_alerts = collect_alerts(customer)
      next if customer_alerts.empty?

      customer.alerts = customer_alerts
      process_endpoint_alerts(customer, customer_alerts)
    end
  end

  # Processes alerts for a single customer and adds them to all_alerts.
  #
  # @param customer [Object] The customer object being processed.
  # @param all_alerts [Hash] The hash storing all alerts.
  #
  def process_customer_alerts(customer, all_alerts)
    description = customer.description
    cfg = @config.by_description(description)
    return unless cfg.monitor_backup

    all_alerts[customer.id] = customer_alerts = CustomerAlerts.new(description, customer.alerts)
    customer_alerts.customer = customer

    return if customer.alerts.empty?

    @report.puts '', description
    # Process all endpoint alerts
    customer.endpoints.each_value do |ep|
      next unless ep.alerts.count.positive?

      @report.puts "- Endpoint #{ep}"
      ep.alerts.each do |a|
        severity = a.severity
        next if severity.eql?('Resolved')

        customer_alerts.add_incident(a.endpoint_id, a, IntegraBackupIncident)
        @report.puts "  #{a.created} #{severity} #{a.description} "
      end
    end
  end

  # Processes and associates alerts to their respective endpoints.
  #
  # @param customer [Object] The customer object.
  # @param customer_alerts [Hash] The alerts collected for the customer.
  #
  def process_endpoint_alerts(customer, customer_alerts)
    customer_alerts.each_value do |a|
      next if %w[Success Running].include?(a.severity)

      endpoint_id = a.endpoint_id
      create_endpoint_from_alert(customer, a) unless customer.endpoints[endpoint_id]
      customer.endpoints[endpoint_id]&.alerts&.push(a)
    end
  end
end
