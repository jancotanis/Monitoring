# frozen_string_literal: true

require 'dotenv'
require 'json'

require_relative 'utils'
require_relative 'SkykickAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

SKYKICK = 'Skykick'
class SkykickBackupIncident < MonitoringIncident
  def initialize(device = nil, start_time = nil, end_time = nil, alert = nil)
    super(SKYKICK, device, start_time, end_time, alert)
  end

  def endpoint_to_s
    alert.endpoint_type.to_s
  end
end

class SkykickMonitor < AbstractMonitor
  attr_reader :config, :all_alerts

  def initialize(report, config, log)
    super(
      SKYKICK,
      Skykick::ClientWrapper.new(ENV.fetch('SKYKICK_CLIENT_ID'), ENV.fetch('SKYKICK_CLIENT_SECRET'), log),
      report,
      config,
      log
    )
  end

  private

  def collect_data
    @tenants.each do |customer|
      customer.clear_endpoint_alerts
      cfg = @config.by_description(customer.description)
      if cfg.monitor_backup
        customer_alerts = collect_alerts(customer)
        # add active alerts to customer record
        if customer_alerts.count.positive?
          customer.alerts = customer_alerts
          customer_alerts.each_value do |a|
            unless a.severity.eql? 'Information'
              create_endpoint_from_alert(customer, a) unless customer.endpoints[a.endpoint_id]
              customer.endpoints[a.endpoint_id].alerts << a if customer.endpoints[a.endpoint_id]
            end
          end
        end
      end
      # throttle api
      sleep(0.05)
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
          if !a.severity.eql? 'Resolved'
            customer_alerts.add_incident(a.endpoint_id, a, SkykickBackupIncident)
            @report.puts "  #{a.created} #{a.severity} #{a.description} "
          end
        end
      end
    end
  end
end
