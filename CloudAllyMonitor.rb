# frozen_string_literal: true

require 'dotenv'
require 'json'
require 'cloudally'

require_relative 'CloudAllyAPI'
require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

CLOUDALLY = 'CloudAlly'
class CloudBackupIncident < MonitoringIncident
  def initialize(device = nil, start_time = nil, end_time = nil, alert = nil)
    super(CLOUDALLY, device, start_time, end_time, alert)
  end

  def endpoint_to_s
    alert.endpoint_type.to_s
  end
end

class CloudAllyMonitor < AbstractMonitor
  attr_reader :config, :all_alerts

  def initialize(report, config, log)
    client = CloudAlly::ClientWrapper.new(
      ENV.fetch('CLOUDALLY_CLIENT_ID'),
      ENV.fetch('CLOUDALLY_CLIENT_SECRET'),
      ENV.fetch('CLOUDALLY_USER'),
      ENV.fetch('CLOUDALLY_PASSWORD'),
      log
    )
    super(CLOUDALLY, client, report, config, log)
  end

  private

  # Monitor when backup is on
  def monitor_tenant?(cfg)
    cfg.monitor_backup
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
      next unless customer_alerts.count.positive?

      customer.alerts = customer_alerts
      customer_alerts.each do |a|
        next unless a.severity.eql? 'FAILED'

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
    return unless cfg.monitor_backup

    all_alerts[customer.id] = customer_alerts = CustomerAlerts.new(description, customer.alerts)
    customer_alerts.customer = customer

    return if customer.alerts.empty?

    @report.puts '', description
    # walk through all endpoint elerts
    customer.endpoints.each_value do |ep|
      if ep.alerts.any?
        @report.puts "- Endpoint #{ep}"
        ep.alerts.each do |a|
          # group alerts by customer
          unless a.severity.eql? 'Resolved'
            customer_alerts.add_incident(a.endpoint_id, a, CloudBackupIncident)
            @report.puts "  #{a.created} #{a.severity} #{a.description} "
          end
        end
      end
    end
  end
end
