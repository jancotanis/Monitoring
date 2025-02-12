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
      ENV['CLOUDALLY_CLIENT_ID'],
      ENV['CLOUDALLY_CLIENT_SECRET'],
      ENV['CLOUDALLY_USER'],
      ENV['CLOUDALLY_PASSWORD'],
      log
    )
    super(CLOUDALLY, client, report, config, log)
  end

  private

  def collect_data
    @tenants.each do |customer|
      customer.clear_endpoint_alerts
      # add endpoints to customer
      endpts = @client.endpoints(customer.id)
      endpts.each do |e|
        customer.endpoints[e.id] = e
      end

      cfg = @config.by_description(customer.description)
      if cfg.monitor_backup
        customer_alerts = collect_alerts(customer)
        # add active alerts to customer record
        if customer_alerts.count.positive?
          customer.alerts = customer_alerts
          customer_alerts.each do |a|
            if a.severity.eql? 'FAILED'
              create_endpoint_from_alert(customer, a) unless customer.endpoints[a.endpoint_id]
              customer.endpoints[a.endpoint_id].alerts << a if customer.endpoints[a.endpoint_id]
            end
          end
        end
      end
    end
  end

  # Processes alerts for a single customer and adds them to all_alerts.
  #
  # @param customer [Object] The customer object being processed.
  # @param all_alerts [Hash] The hash storing all alerts.
  #
  def process_customer_alerts(customer, all_alerts)
    cfg = @config.by_description(customer.description)
    return unless cfg.monitor_backup

    all_alerts[customer.id] = customer_alerts = CustomerAlerts.new(customer.description, customer.alerts)
    customer_alerts.customer = customer

    return if customer.alerts.empty?

    @report.puts '', customer.description
    # walk through all endpoint elerts
    customer.endpoints.each_value do |ep|
      if ep.alerts.count.positive?
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
