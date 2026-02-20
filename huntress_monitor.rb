# frozen_string_literal: true

require 'dotenv'
require 'json'
require 'huntress'

require_relative 'huntress_api'
require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

HUNTRESS = 'Huntress'
class CyberIncident < MonitoringIncident
  def initialize(device = nil, start_time = nil, end_time = nil, alert = nil)
    super(HUNTRESS, device, start_time, end_time, alert)
  end

  def endpoint_to_s
    # TODO: check if good desc
    alert.endpoint_type.to_s
  end
end

class HuntressMonitor < AbstractMonitor
  attr_reader :config, :all_alerts

  def initialize(report, config, log)
    client = Huntress::ClientWrapper.new(
      ENV.fetch('HUNTRESS_API_KEY'),
      ENV.fetch('HUNTRESS_API_SECRET'),
      log
    )
    super(HUNTRESS, client, report, config, log)
  end

  private

  # Monitor when backup is on
  def monitor_tenant?(cfg)
    cfg.monitor_endpoints
  end

  def collect_data
    process_active_tenants do |customer, _cfg|
      # add endpoints to customer
      endpts = @client.endpoints(customer.id)
      endpts.each do |ep|
        customer.endpoints[ep.id] = ep
      end

      customer_alerts = collect_alerts(customer)
      # add active alerts to customer record
      next unless customer_alerts.any?

      customer.alerts = customer_alerts
      customer_alerts.each do |a|
#        next unless a.severity.eql? 'FAILED'

        endpoint_id = a.endpoint_id
        create_endpoint_from_alert(customer, a) unless customer.endpoints[endpoint_id]
        customer.endpoints[endpoint_id]&.alerts&.push(a)
      end
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
    return unless monitor_tenant?(cfg)

    all_alerts[customer.id] = customer_alerts = CustomerAlerts.new(description, customer.alerts)
    customer_alerts.customer = customer

    return if customer.alerts.empty?

    @report.puts '', description
    # walk through all endpoint elerts
    customer.endpoints.each_value do |ep|
      next unless ep.alerts.any?

      @report.puts "- Endpoint #{ep}"
      ep.alerts.each do |a|
        # group alerts by customer
        unless a.severity.eql? 'closed'
          customer_alerts.add_incident(a.endpoint_id, a, CyberIncident)
          @report.puts "  #{a.created} #{a.severity} #{a.description} "
        end
      end
    end
  end
end
