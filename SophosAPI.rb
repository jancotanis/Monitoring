# frozen_string_literal: true

require 'logger'
require 'sophos_central_api'

require_relative 'utils'
require_relative 'MonitoringModel'

##
# The Sophos module provides integration with the Sophos monitoring and alerting system.
# It defines structures for handling tenant data, endpoints, and alerts.
#
module Sophos

  ##
  # Represents a tenant in the Sophos system.
  #
  # @attr [String] id The tenant ID.
  # @attr [String] name The tenant name.
  # @attr [String] api The API host associated with the tenant.
  # @attr [String] status The tenant's current status.
  # @attr [String] billing_type The billing type associated with the tenant.
  # @attr [Hash] raw_data Additional attributes related to the tenant.
  # @attr [Hash] endpoints A hash of endpoints associated with the tenant.
  # @attr [Array] alerts A list of alerts associated with the tenant.
  #
  TenantData = Struct.new(:id, :name, :api, :status, :billing_type, :raw_data, :endpoints, :alerts) do
    include MonitoringTenant

    ##
    # Initializes a new tenant instance.
    #
    # @param [String] id The tenant ID.
    # @param [String] name The tenant name.
    # @param [String] api The API host of the tenant.
    # @param [String] status The tenant status.
    # @param [String] billing_type The billing type.
    # @param [Hash] raw_data Additional attributes.
    # @param [Hash] endpoints Endpoints associated with the tenant.
    # @param [Array] alerts A list of alerts associated with the tenant.
    #
    def initialize(*)
      super
      self.endpoints ||= {}
      self.alerts ||= []
    end

    ##
    # Determines if the tenant is on a trial subscription.
    #
    # @return [Boolean] True if the billing type is 'trial', false otherwise.
    #
    def trial?
      'trial'.eql?(billing_type)
    end

    ##
    # Returns the API host of the tenant. Alias method.
    #
    # @return [String] The API host.
    #
    def apiHost
      api
    end

    ##
    # Initializes lazy loading for endpoints.
    #
    # @param [Proc] loader A callable to fetch the endpoints when required.
    #
    def lazy_endpoints_loader(loader)
      self[:endpoints] = nil
      define_singleton_method(:endpoints) do
        self[:endpoints] ||= loader.call
        self[:endpoints]
      end
    end
  end

  ##
  # Represents an endpoint in the Sophos system.
  #
  class EndpointData < MonitoringEndpoint; end

  ##
  # Represents an alert in the Sophos system.
  #
  # @attr [String] id The alert ID.
  # @attr [Time] created The time the alert was created.
  # @attr [String] description The alert description.
  # @attr [String] severity The severity level of the alert.
  # @attr [String] category The category of the alert.
  # @attr [String] product The associated product.
  # @attr [String] endpoint_id The endpoint ID related to the alert.
  # @attr [String] endpoint_type The type of the endpoint related to the alert.
  # @attr [Hash] raw_data Additional data related to the alert.
  #
  AlertData = Struct.new(:id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data) do
    ##
    # Creates a new endpoint associated with the alert.
    #
    # @return [Sophos::EndpointData] A new endpoint created for the alert.
    #
    def create_endpoint
      Sophos::EndpointData.new(endpoint_id, "#{property('managedAgent.type')}/#{property('product')}", property('managedAgent.name'))
    end

    ##
    # Retrieves the type of the alert from its properties. This will be used to summarize device alerts.
    #
    # @return [String] The alert type.
    #
    def type
      property('type')
    end
  end

  ##
  # Provides a wrapper for interacting with the Sophos API.
  #
  class ClientWrapper
    attr_reader :api

    ##
    # Initializes the Sophos client with the given authentication credentials.
    #
    # @param [String] client_id The client ID used for authentication.
    # @param [String] client_secret The client secret used for authentication.
    # @param [Boolean] log Whether to enable logging (default is true).
    #
    def initialize(client_id, client_secret, log = true)
      Sophos.configure do |config|
        config.client_id = client_id
        config.client_secret = client_secret
        config.logger = Logger.new(FileUtil.daily_file_name('sophos.log')) if log
      end
      @api = Sophos.client
      @api.login
    end

    ##
    # Retrieves all tenants from the Sophos system.
    #
    # @return [Array<TenantData>] A list of all tenant objects.
    #
    def tenants
      unless @tenants
        @tenants = {}
        data = @api.tenants
        data.each do |item|
          t = TenantData.new(item.id, item.showAs, item.apiHost, item.status, item.billingType, item.attributes)
          @tenants[t.id] = t
          t.lazy_endpoints_loader(-> { endpoints(t) })
        end
      end
      @tenants.values
    end

    ##
    # Retrieves a specific tenant by its ID.
    #
    # @param [String] id The tenant ID.
    # @return [TenantData] The tenant object associated with the given ID.
    #
    def tenant_by_id(id)
      tenants unless @tenants
      @tenants[id]
    end

    ##
    # Retrieves all endpoints associated with a specific customer.
    #
    # @param [TenantData] customer The customer object for which endpoints are being fetched.
    # @return [Hash] A hash of endpoint objects associated with the customer.
    # @raise [Sophos::SophosError] In case of any errors encountered while fetching endpoints.
    #
    def endpoints(customer)
      endp = {}
      data = @api.client(customer).endpoints
      data.each do |item|
        status = item.health.overall if item.attributes.key? 'health'
        group_name = item.group.name if item.attributes.key? 'group'
        endp[item.id] = EndpointData.new(item.id, item.type, item.hostname, group_name, status, item.attributes)
      end
      endp
    rescue Sophos::SophosError => e
      @logger&.error e
      @logger&.error e.response.to_json
    end

    ##
    # Retrieves all alerts associated with a specific customer.
    #
    # @param [TenantData] customer The customer object for which alerts are being fetched.
    # @return [Hash] A hash of alert IDs mapped to alert objects.
    #
    def alerts(customer)
      @alerts = {}
      customer.clear_endpoint_alerts
      data = @api.client(customer).alerts
      data.each do |item|
        a = AlertData.new(
          item.id, item.raisedAt, item.description, item.severity, item.category, item.product,
          item.managedAgent.id, item.managedAgent.type, item.attributes
        )
        @alerts[a.id] = a
      end
      @alerts
    end

    ##
    # Retrieves all security information and event management (SIEM) alerts for a specific customer.
    #
    # @param [TenantData] customer The customer object for which SIEM alerts are being fetched.
    # @return [Hash] A hash of alert IDs mapped to SIEM alert objects.
    #
    def siem(customer)
      @alerts = {}

      data = @api.client(customer).get('/siem/v1/alerts')
      # :id, :description, :severity, :category, :product, :actions
      data.each do |item|
        a = AlertData.new(
          item.id, item.when, item.description, item.severity, item.category, item.product,
          item.data.endpoint_id, item.data.endpoint_type, item.attributes
        )
        @alerts[a.id] = a
      end
      @alerts
    end
  end
end
