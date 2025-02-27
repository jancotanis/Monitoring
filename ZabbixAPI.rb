# frozen_string_literal: true

require 'logger'
require 'zabbix_api_gem'

require_relative 'utils'
require_relative 'MonitoringModel'

##
# The Zabbix module provides integration with Zabbix monitoring.
# It defines structures for handling tenant data, endpoints, and alerts.
#
module Zabbix

  ##
  # Represents a tenant in the Zabbix system.
  #
  # @attr [String] id The tenant ID.
  # @attr [String] name The tenant name.
  # @attr [String, nil] status The tenant status.
  # @attr [Hash] raw_data Additional attributes.
  # @attr [Array] endpoints The tenant's endpoints.
  # @attr [Array] alerts The tenant's alerts.
  #
  TenantData = Struct.new(:id, :name, :status, :raw_data, :endpoints, :alerts) do
    include MonitoringTenant

    ##
    # Initializes a new tenant instance.
    #
    def initialize(*)
      super
      self.alerts ||= []
    end

    ##
    # Lazy loads endpoints using a provided loader function.
    #
    # @param [Proc] loader A lambda function that fetches endpoints.
    #
    def lazy_endpoints_loader(loader)
      self[:endpoints] = nil
      define_singleton_method(:endpoints) do
        self[:endpoints] ||= loader.call
      end
    end
  end

  ##
  # Represents an endpoint in Zabbix.
  #
  class EndpointData < MonitoringEndpoint; end

  ##
  # Represents an alert in the Zabbix system.
  #
  # @attr [String] id The alert ID.
  # @attr [Time] created The alert creation time.
  # @attr [String] description Alert description.
  # @attr [Integer] severity_code Alert severity level.
  # @attr [String] category The alert category.
  # @attr [String] product The associated product.
  # @attr [String, nil] endpoint_id The related endpoint ID.
  # @attr [String, nil] endpoint_type The type of endpoint.
  # @attr [Hash] raw_data Additional alert details.
  # @attr [Hash] event The related event.
  #
  AlertData = Struct.new(:id, :created, :description, :severity_code, :category, :product, :endpoint_id, :endpoint_type, :raw_data, :event) do
    include MonitoringAlert

    ##
    # Creates a new endpoint associated with the alert.
    #
    # @return [Zabbix::EndpointData] The newly created endpoint.
    #
    def create_endpoint
      # :id, :type, :hostname, :tenant, :status, :raw_data
      Zabbix::EndpointData.new(id, '?', '?')
    end

    ##
    # Retrieves the severity level as a human-readable string.
    #
    # @return [String] The severity level description.
    #
    def severity
      severity_text = ['not classified', 'information', 'warning', 'average', 'high', 'disaster']
      severity_text.fetch(severity_code.to_i, severity_code)
    end
  end

  ##
  # Provides a wrapper for the Zabbix API.
  #
  class ClientWrapper
    attr_reader :api

    ##
    # Initializes the Zabbix client with authentication. 
    # Use userid and primary key for login information found in https://zabbix-portal/zabbix.php?action=token.list
    #
    # @param [String] host The Zabbix server URL.
    # @param [String] auth_token The authentication token.
    # @param [Boolean] log Whether to enable logging.
    #
    def initialize(host, auth_token, log = true)
      Zabbix.configure do |config|
        config.endpoint = host
        config.access_token = auth_token
        config.logger = Logger.new(FileUtil.daily_file_name('zabbix.log')) if log
      end
      @api = Zabbix.client
      @api.login
    end

    ##
    # Retrieves all tenants from Zabbix.
    #
    # @return [Array<TenantData>] A list of tenant objects.
    #
    def tenants
      unless @tenants
        @tenants = {}

        data = @api.hostgroups
        data.each do |item|
          td = TenantData.new(item.groupid, item.name, nil, item.attributes)
          @tenants[td.id] = td
          # Lazy loading of endpoints
          td.lazy_endpoints_loader(-> { endpoints(td) })
        end
      end
      @tenants.values
    end

    ##
    # Fetches endpoints associated with a specific tenant.
    #
    # @param [TenantData] customer The tenant object.
    # @return [Hash] A hash of endpoints mapped by host ID.
    #
    def endpoints(customer)
      endp = {}

      data = @api.hosts({ groupids: [customer.id], output: 'extend', selectInventory: 'extend' })
      # :id, :type, :hostname, :group, :status, :raw_data, :alerts
      data.each do |item|
        e = endp[item.hostid] = EndpointData.new(item.hostid, 'zabbix item', item.name, customer.id, item.status, item.attributes)
        type = e.property('inventory.type')
        e.type = type unless type.to_s.empty?
      end
      endp
    end

    ##
    # Retrieves active alerts for a given tenant.
    #
    # @param [TenantData, nil] customer The tenant object (optional).
    # @return [Hash] A hash of alerts mapped by event ID.
    #
    def alerts(customer = nil)
      @alerts = {}

      query = customer ? { groupids: [customer.id] } : nil
      data = @api.problems(query)

      # :id,:created,:description,:severity_code,:category,:product,:endpoint_id,:endpoint_type,:raw_data,:event
      data.each do |item|
        a = AlertData.new(
          item.eventid, @api.zabbix_clock(item.clock), item.name.strip, item.severity, item.object, 'zabbix',
          nil, nil, item.attributes
        )

        event = events_by_id(a.id).first
        if event.hosts
          h = event.hosts.first
          a.endpoint_id = h.hostid
          puts "* Host #{a.endpoint_id} exists in multiple Zabbix groups" if event.hosts.count > 1
        end
        @alerts[a.id] = a
      end
      @alerts
    end

    private

    ##
    # Fetches events by ID, including associated hosts.
    #
    # @param [Array<String>, String] id The event ID or array of IDs.
    # @return [Array] A list of event objects.
    #
    def events_by_id(id)
      id = [id] unless id.is_a? Array
      # get events including hostid for the object that created the event
      @api.event(id, { selectHosts: ['hostid'] })
    end
  end
end
