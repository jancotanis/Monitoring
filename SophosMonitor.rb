# frozen_string_literal: true

require 'json'
require 'yaml'

require_relative 'utils'
require_relative 'SophosAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

SOPHOS = 'Sophos'
CONNECTIVITY = 'connectivity'
class SophosIncident < MonitoringIncident
  def initialize(device = nil, start_time = nil, end_time = nil, alert = nil)
    super(SOPHOS, device, start_time, end_time, alert)
  end
end

class EndpointIncident < SophosIncident
  def endpoint_to_s
    alert.property('managedAgent.type') + ' ' + alert.property('managedAgent.name')
  end

  def to_s
    person = "   User:        #{alert.property('person.name')}\n" unless alert.property('person.name').empty?
    "  #{time_to_s}: #{source} #{alert.severity} alert\n" \
    "   Description: #{alert.description}\n" \
    "   Endpoint:    #{alert.endpoint_type}\n" \
    "#{person}" \
    "   Resolution:  #{alert.property('allowedActions')}"
  end
end

class ConnectivityIncident < SophosIncident
  def endpoint_to_s
    alert.endpoint_type
  end

  def to_s
    "  #{time_to_s}: #{source} #{alert.severity} alert '#{alert.description}' for #{alert.endpoint_type}"
  end
end

class SophosMonitor < AbstractMonitor
  attr_reader :config, :all_alerts, :tenants

  def initialize(report, config, log)
    client = Sophos::ClientWrapper.new(ENV['SOPHOS_CLIENT_ID'], ENV['SOPHOS_CLIENT_SECRET'], log)
    super(SOPHOS, client, report, config, log)
    @products = {}
    load_tenants
    @config.load_config(source, @tenants)
  end

  def run(all_alerts)
    collect_data
    @tenants.each do |customer|
      cfg = @config.by_description(customer.description)
      if cfg.monitoring?
        cfg.endpoints = customer.endpoints.count if customer.endpoints.count.positive?
        all_alerts[customer.id] = customer_alerts = CustomerAlerts.new(customer.description, customer.alerts)
        customer_alerts.customer = customer
        if customer.alerts.count.positive?
          @report.puts '', "#{customer.description} - license=#{customer.billing_type}"

          # group alerts by customer
          _count = handle_endpoint_alerts(customer_alerts) if cfg.monitor_endpoints

          connection_errors = 0
          ## connection_errors = handle_connectivity_alerts( customer_alerts ) if cfg.monitor_connectivity

          customer_alerts.devices.each do |device_id, incidents|
            endpoint = customer.endpoints[device_id]
            @report.puts "- #{endpoint}"
            incidents.each do |_type, incident|
              @report.puts incident.to_s
            end
          end
          @report.puts "  connectivity alerts: #{connection_errors}" if connection_errors.positive?
        end
      end
    end

    FileUtil.write_file(FileUtil.daily_file_name(source.downcase + '-alerts.json'), all_alerts.to_json)
    all_alerts
  end

  def handle_unique_alerts(customer, &block)
    # hgash to collect unique alerts
    customer.alerts.each_value do |a|
      block.call customer.devices, a
    end
    customer.devices
  end

  def handle_connectivity_alerts(customer)
    connection_errors = 0
    _endpoints = handle_unique_alerts(customer) do |_ep, a|
      if CONNECTIVITY.eql?(a.category)
        connection_errors += 1
        customer.add_incident(a.endpoint_id, a, ConnectivityIncident)
      end
    end
    connection_errors
  end

  def handle_endpoint_alerts(customer)
    endpoints = handle_unique_alerts(customer) do |_ep, a|
      customer.add_incident(a.endpoint_id, a, EndpointIncident) unless CONNECTIVITY.eql?(a.category)
    end
    endpoints.count
  end

  def load_tenants
    @tenants = @client.tenants.sort_by { |t| t.description.upcase }
  end

  def report_endpoints
    @tenants.each do |customer|
      cfg = @config.by_description(customer.description)

      if cfg.monitoring?
        customer.endpoints.each do |e|
          puts e
        end
      end
    end
  end

private

  def collect_data
    @tenants.each do |customer|
      cfg = @config.by_description(customer.description)
      if cfg.monitoring?
        alerts = @client.alerts(customer)
        # add active alerts to customer record
        if alerts.count.positive?
          find_products(alerts)
          customer.alerts = alerts
          alerts.each_value do |a|
            create_endpoint_from_alert(customer, a) unless customer.endpoints[a.endpoint_id]
            customer.endpoints[a.endpoint_id].alerts << a
          end
        end
      end
      # throuttle sophos api
      sleep(0.2)

    rescue => e
      if customer.trial?
        puts '', "*** Trial customer skipped #{customer.description}"
      else
        @report.puts '', "*** Error with #{customer.description}"
        @report.puts e
      end
    end
  end

  def find_products(alerts)
    alerts.each_value do |a|
      @products[a.product] = a.product
    end
  end
end
