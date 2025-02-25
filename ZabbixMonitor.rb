# frozen_string_literal: true

require 'json'
require 'yaml'

require_relative 'utils'
require_relative 'ZabbixAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

ZABBIX = 'Zabbix'
Z_MINIMUM_SEVERITY = '3' # average

class ZabbixIncident < MonitoringIncident
  def initialize(device = nil, start_time = nil, end_time = nil, alert = nil)
    super(ZABBIX, device, start_time, end_time, alert)
  end

  def endpoint_to_s
    device.to_s
  end

  def to_s
    "  #{time_to_s}: #{source} #{alert.severity} alert\n" \
      "   Description: #{alert.description}\n"
  end
end

class ZabbixMonitor < AbstractMonitor
  attr_reader :config, :all_alerts, :tenants

  def initialize(report, config, log)
    client = Zabbix::ClientWrapper.new(ENV.fetch('ZABBIX_API_HOST'), ENV.fetch('ZABBIX_API_KEY'), log)
    super(ZABBIX, client, report, config, log)
  end

  private

  # Monitor when endpoints is on
  def monitor_tenant?(cfg)
    cfg.monitor_endpoints
  end

  def collect_data
    process_active_tenants do |customer, _cfg|
      alerts = @client.alerts(customer)
      # add active alerts to customer record
      if alerts.count.positive?
        customer.alerts = alerts
        alerts.each_value do |a|
          create_endpoint_from_alert(customer, a) unless customer.endpoints[a.endpoint_id]
          customer.endpoints[a.endpoint_id].alerts << a
        end
      end
    end
  rescue Zabbix::ZabbixError => e
    @report.puts '', "*** Error with #{customer.description}"
    @report.puts e
  end

  # Processes alerts for a single customer and adds them to all_alerts.
  #
  # @param customer [Object] The customer object being processed.
  # @param all_alerts [Hash] The hash storing all alerts.
  #
  def process_customer_alerts(customer, all_alerts)
    cfg = @config.by_description(customer.description)
    return unless cfg.monitor_connectivity

    cfg.endpoints = customer.endpoints.count if customer.endpoints.count.positive?
    all_alerts[customer.id] = customer_alerts = CustomerAlerts.new(customer.description, customer.alerts)
    customer_alerts.customer = customer

    return if customer.alerts.empty?

    @report.puts '', customer.description

    customer.endpoints.each_value do |ep|
      next unless ep.alerts.count.positive?

      @report.puts "- Endpoint #{ep}"
      ep.alerts.each do |a|
        # group alerts by customer
        if a.severity_code >= Z_MINIMUM_SEVERITY
          customer_alerts.add_incident(a.endpoint_id, a, ZabbixIncident)
          @report.puts "  #{a.created} #{a.severity} #{a.description} "
        end
      end
    end
  end
end
