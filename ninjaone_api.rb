# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../apies/ninjaone/lib', __dir__)
require 'ninjaone'
require 'logger'

require_relative 'utils'
require_relative 'MonitoringModel'

##
# The Huntress module provides integration with the Huntress Cybersec platform.
# It defines structures for handling tenant data, endpoints, and alerts related to security incidents.
#
module NinjaOne
  ##
  # Represents an organization in the NinjaOne system.
  #
  # @attr [String] id The tenant ID.
  # @attr [String] name The name of the tenant.
  # @attr [String] status The status of the tenant.
  # @attr [Hash] raw_data Additional data related to the tenant.
  # @attr [Hash] endpoints A hash of endpoints associated with the tenant.
  # @attr [Array] alerts A list of alerts associated with the tenant.
  #
  TenantData = Struct.new(:id, :name, :status, :raw_data, :endpoints, :alerts) do
    include MonitoringTenant

    ##
    # Initializes a new tenant instance.
    #
    # @param [String] id The tenant ID.
    # @param [String] name The tenant's name.
    # @param [String] status The tenant's status.
    # @param [String] billing_type The tenant's billing type.
    # @param [Hash] raw_data Additional data related to the tenant.
    # @param [Hash] endpoints A hash of endpoints associated with the tenant.
    # @param [Array] alerts A list of alerts associated with the tenant.
    #
    def initialize(*)
      super
      self.endpoints ||= {}
      self.alerts ||= []
    end
  end

  ##
  # Represents an endpoint in the Huntress system.
  #
  class EndpointData < MonitoringEndpoint; end

  ##
  # Represents an alert for task statusses in the Huntress  system.
  #
  # @attr [String] id The alert ID.
  # @attr [Time] created The time the alert was created.
  # @attr [String] description The alert's description.
  # @attr [String] severity The severity level of the alert.
  # @attr [String] category The category of the alert.
  # @attr [String] product The associated product.
  # @attr [String] endpoint_id The endpoint ID related to the alert.
  # @attr [String] endpoint_type The type of the endpoint related to the alert.
  # @attr [Hash] raw_data Additional data related to the alert.
  #
  AlertData = Struct.new(:id, :created, :description, :severity, :category,
                         :product, :endpoint_id, :endpoint_type, :tenant, :raw_data) do
    include MonitoringAlert

    ##
    # Creates a new endpoint associated with the alert.
    #
    # @return [Huntress::EndpointData] A new endpoint created for the alert.
    #
    def create_endpoint
      NinjaOne::EndpointData.new(endpoint_id, category, endpoint_type)
    end
  end

  ##
  # Provides a wrapper for interacting with the Huntress API.
  #
  class ClientWrapper
    attr_reader :api

    ##
    # Initializes the Huntress client with the given credentials.
    #
    # @param [String] client_id The client ID for authentication.
    # @param [String] client_secret The client secret for authentication.
    # @param [String] user The username for authentication.
    # @param [String] password The password for authentication.
    # @param [Boolean] log Whether to enable logging (default is true).
    #
    def initialize(host, client_id, client_secret, log = true)
      @tenants = nil
      @endpoints = nil
      @alerts = nil
      @backup_alerts = nil
      NinjaOne.configure do |config|
        config.endpoint = host
        config.client_id = client_id
        config.client_secret = client_secret
        config.logger = Logger.new(FileUtil.daily_file_name('ninjaone.log')) if log
      end
      @api = NinjaOne.client
      @api.login
    end

    ##
    # Retrieves all tenants from the Huntress system.
    #
    # @return [Array<TenantData>] A list of all tenant objects.
    #
    def tenants
      unless @tenants
        @tenants = {}
        data = @api.organizations
        data.each do |item|
          @tenants[item.id] = TenantData.new(item.id, item.name, nil, item.attributes)
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
    # Retrieves all endpoints associated with a given tenant.
    #
    # @param [TenantData] tenant The tenant object to fetch the endpoints for.
    # @return [Array<EndpointData>] A list of endpoints associated with the given tenant.
    #
    def endpoints(tenant)
      @endpoints ||= load_endpoints
      @endpoints.values.select { |endp| tenant.eql?(endp.tenant) }
    end

    ##
    # Load endpoint by id.
    #
    # @param [integer] id The id of the endpoint.
    # @return [Array<EndpointData>] The endpoint or nil if not found.
    #
    def endpoint(id)
      @endpoints ||= load_endpoints
      @endpoints[id]
    end

    ##
    # Retrieves all alerts associated with a given tenant.
    #
    # @param [TenantData, NilClass] tenant The tenant object to fetch the alerts for. If nil, returns all alerts.
    # @return [Array<AlertData>] A list of alerts associated with the given tenant,
    #                            or all alerts if no tenant is provided.
    #
    def alerts(tenant = nil)
      @alerts ||= load_alerts
      if tenant
        @alerts.values.select { |alert| tenant.eql?(alert.tenant) }
      else
        @alerts.values
      end
    end

    ##
    # Retrieves all alerts associated with a given tenant.
    #
    # @param [TenantData, NilClass] tenant The tenant object to fetch the alerts for. If nil, returns all alerts.
    # @return [Array<AlertData>] A list of alerts associated with the given tenant,
    #                            or all alerts if no tenant is provided.
    #
    def backup_alerts(tenant = nil)
      @backup_alerts ||= load_backup_alerts
      if tenant
        @backup_alerts.values.select { |alert| tenant.eql?(alert.tenant) }
      else
        @backup_alerts.values
      end
    end

    private

    ##
    # Loads all endpoints for the Huntress system.
    #
    # @return [Hash] A hash of endpoint IDs mapped to endpoint objects.
    #
    def load_endpoints
      @endpoints = {}
      data = @api.devices
      data.each do |item|
        # status true is online, false is offline
        @endpoints[item.id] = EndpointData.new(item.id, item.nodeClass, item.systemName, item.organizationId, !item.offline, item.attributes)
      end
      @endpoints
    end

    ##
    # Loads all alerts for the NinjaOne system.
    #
    # @return [Hash] A hash of alert IDs mapped to alert objects.
    #
    def load_alerts
      @alerts = {}
#      data = @api.signals
#      data.each do |item|
#        alert = AlertData.new(
#                  item.id, item.created_at, item.name, item.status,
#                  item.type, item.type, item.entity.id, item.entity.name, item.organization.id, item.attributes
#                )
#        @alerts[item.id] = alert
#      end
      @alerts
    end

    ##
    # Loads all alerts for the NinjaOne system.
    #
    # @return [Hash] A hash of alert IDs mapped to alert objects.
    #
    def load_backup_alerts
      @backup_alerts = {}
      # get all failed backup jobs
      data = @api.backup_jobs(sf: 'status = FAILED')
      data.each do |item|
        type_description = if (endpoint = endpoint(item.deviceId))
                             endpoint.to_s
                           else
                             'did not fetch endpoint type'
                           end
        alert = AlertData.new(
          item.jobId, Time.at(item.jobStartTime).to_datetime, item.planName, item.jobStatus, 'backup',
          'NinjaOne Backup', item.deviceId, type_description, item.organizationId, item.attributes
        )
        # assuem oldest first
        @backup_alerts[item.jobId] = alert
      end

      @backup_alerts
    end
  end
end
