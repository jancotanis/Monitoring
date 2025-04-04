# frozen_string_literal: true

require 'dotenv'
require 'json'

require_relative 'utils'
require_relative 'VeeamAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

VEEAM = 'Veeam'

class VeeamBackupIncident < MonitoringIncident
  def initialize(device = nil, start_time = nil, end_time = nil, alert = nil)
    super(VEEAM, device, start_time, end_time, alert)
  end

  def endpoint_to_s
    "#{alert.property('object.type')} #{alert.property('object.computerName')} #{alert.property('object.objectName')}"
  end
end

class VeeamMonitor < AbstractMonitor
  attr_reader :config, :all_alerts

  RESOLVED = 'Resolved'

  def initialize(report, config, log)
    client = Veeam::ClientWrapper.new(ENV.fetch('VEEAM_API_HOST'), ENV.fetch('VEEAM_API_KEY'), log)
    super(VEEAM, client, report, config, log)

    @alerts = @client.alerts
  end

  private

  # Monitor when backup is on
  def monitor_tenant?(cfg)
    cfg.monitor_backup
  end

  def collect_data
    process_active_tenants do |customer, _cfg|
      customer_alerts = collect_alerts(customer)
      # add active alerts to customer record
      if customer_alerts.any?
        customer.alerts = customer_alerts
        customer_alerts.each_value do |a|
          endpoint_id = a.endpoint_id
          create_endpoint_from_alert(customer, a) unless customer.endpoints[endpoint_id]
          customer.endpoints[endpoint_id]&.alerts&.push(a)
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
    # walk through all endpoint alerts
    customer.endpoints.each_value do |ep|
      next unless ep.alerts.any?

      @report.puts "- Endpoint #{ep}"
      ep.alerts.each do |a|
        # group alerts by customer
        if a.severity.eql? RESOLVED
          # resolved alert, maybe remove from reported_alerts
          @report.puts "  #{a.created} #{a.severity} #{a.description} #{a.id}"
          veeam_id = "#{VEEAM}-#{a.id}"
          if cfg.reported_alerts.include? veeam_id
            cfg.reported_alerts.delete(veeam_id)
            @report.puts "  remove resolved alert #{a.created} #{a.severity} #{a.description} (#{veeam_id})"
          end
        else
          customer_alerts.add_incident(a.endpoint_id, a, VeeamBackupIncident)
          @report.puts "  #{a.created} #{a.severity} #{a.description} "
        end
      end
    end
  end

  def collect_alerts(tenant)
    ca = @alerts.values.select { |a| tenant.id.eql?(a.property('object.organizationUid')) }
    result = {}
    ca.each do |a|
      a.company = tenant.description
      result[a.id] = a
    end
    result
  end
end
