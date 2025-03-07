# frozen_string_literal: true

require 'cloudally'
require 'logger'

require_relative 'utils'
require_relative 'MonitoringModel'

##
# The CloudAlly module provides integration with the CloudAlly backup and alerting system.
# It defines structures for handling tenant data, endpoints, and alerts related to backup tasks.
#
module CloudAlly
  # The constant for filtering backup statuses that have "FAILED" status.
  STATUS_WANTED = 'FAILED'

  ##
  # Represents a tenant in the CloudAlly system.
  #
  # @attr [String] id The tenant ID.
  # @attr [String] name The name of the tenant.
  # @attr [String] status The status of the tenant.
  # @attr [String] billing_type The billing type associated with the tenant (e.g., term, trial, usage).
  # @attr [Hash] raw_data Additional data related to the tenant.
  # @attr [Hash] endpoints A hash of endpoints associated with the tenant.
  # @attr [Array] alerts A list of alerts associated with the tenant.
  #
  TenantData = Struct.new(:id, :name, :status, :billing_type, :raw_data, :endpoints, :alerts) do
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
  # Represents an endpoint in the CloudAlly system.
  #
  class EndpointData < MonitoringEndpoint; end

  ##
  # Represents an alert for task statusses in the CloudAlly system.
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
                         :product, :endpoint_id, :endpoint_type, :raw_data) do
    include MonitoringAlert

    ##
    # Provides a description for the alert.
    # This method collects the sub-sources that failed the task based on the status.
    #
    # @return [String] The description of the failed sub-sources in the task.
    #
    def description
      # collect subsources that failed the task
      failed_sub_sources = raw_data['backupStatus'].select { |src|
                                                             STATUS_WANTED.eql? src.status
                                                           }.map(&:subSource).join ' '
      "#{endpoint_type}: #{failed_sub_sources}"
    end

    ##
    # Creates a new endpoint associated with the alert.
    #
    # @return [CloudAlly::EndpointData] A new endpoint created for the alert.
    #
    def create_endpoint
      CloudAlly::EndpointData.new(endpoint_id, category, endpoint_type)
    end
  end

  ##
  # Provides a wrapper for interacting with the CloudAlly API.
  #
  class ClientWrapper
    attr_reader :api

    ##
    # Initializes the CloudAlly client with the given credentials.
    #
    # @param [String] client_id The client ID for authentication.
    # @param [String] client_secret The client secret for authentication.
    # @param [String] user The username for authentication.
    # @param [String] password The password for authentication.
    # @param [Boolean] log Whether to enable logging (default is true).
    #
    def initialize(client_id, client_secret, user, password, log = true)
      @tenants = nil
      @endpoints = nil
      @alerts = nil
      CloudAlly.configure do |config|
        config.client_id = client_id
        config.client_secret = client_secret
        config.username = user
        config.password = password
        config.logger = Logger.new(FileUtil.daily_file_name('cloudally.log')) if log
      end
      @api = CloudAlly.client
      @api.partner_login
    end

    ##
    # Retrieves all tenants from the CloudAlly system.
    #
    # @return [Array<TenantData>] A list of all tenant objects.
    #
    def tenants
      unless @tenants
        @tenants = {}
        data = @api.partner_users
        data.each do |item|
          @tenants[item.id] = TenantData.new(item.id, item.name, item.status, item.discount.to_s, item.attributes)
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
    # Retrieves all alerts associated with a given tenant.
    #
    # @param [TenantData, NilClass] tenant The tenant object to fetch the alerts for. If nil, returns all alerts.
    # @return [Array<AlertData>] A list of alerts associated with the given tenant, or all alerts if no tenant is provided.
    #
    def alerts(tenant = nil)
      @alerts ||= load_alerts
      if tenant
        @alerts.values.select { |alert| tenant.eql?(alert.property('userId')) }
      else
        @alerts.values
      end
    end

    private

    ##
    # Loads all endpoints for the CloudAlly system.
    #
    # @return [Hash] A hash of endpoint IDs mapped to endpoint objects.
    #
    def load_endpoints
      @endpoints = {}
      data = @api.partner_tasks
      data.each do |item|
        @endpoints[item.id] = EndpointData.new(item.id, "#{item.type}/#{item.source}", item.alias, item.userId, item.status, item.attributes)
      end
      @endpoints
    end

    ##
    # Loads all alerts for the CloudAlly system.
    #
    # @return [Hash] A hash of alert IDs mapped to alert objects.
    #
    def load_alerts
      @alerts = {}
      alert_id = 0
      data = @api.partner_status
      data.each do |item|
        alert_id += 1
        alert = create_alert_from_data(alert_id, item)
        @alerts[alert_id] = alert if alert
      end
      @alerts
    end

    ##
    # Creates an alert from the provided data.
    # Filters the alerts for those with the "FAILED" status and generates an alert object.
    #
    # @param [Integer] alert_id The ID for the new alert.
    # @param [Object] item The item containing backup status data.
    # @return [AlertData, NilClass] The created alert object, or nil if no relevant alert.
    #
    def create_alert_from_data(alert_id, item)
      not_actives = item.backupStatus.select { |si| STATUS_WANTED.eql?(si.status) }
      return unless not_actives.count.positive?

      # return new instance
      AlertData.new(
        alert_id, item.lastBackupAttemptDate, not_actives.first.error, not_actives.first.status,
        item.source, item.source, item.taskId, item.entityName, item.attributes
      )
    end
  end
end
