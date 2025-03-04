# frozen_string_literal: true

require 'skykick'
require 'logger'

require_relative 'utils'
require_relative 'MonitoringModel'

##
# The Skykick module provides integration with the Skykick backup and alerting system.
# It defines structures for handling tenant data, endpoints, and alerts related to backups.
#
module Skykick
  ##
  # Represents a tenant in the Skykick system.
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
  # Represents an endpoint in the Skykick system.
  #
  class EndpointData < MonitoringEndpoint; end

  ##
  # Represents an alert in the Skykick system.
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
    # Creates a new endpoint associated with the alert.
    #
    # @return [Skykick::EndpointData] A new endpoint created for the alert.
    #
    def create_endpoint
      Skykick::EndpointData.new(endpoint_id, 'BackupService', property('BackupMailboxId').to_s)
    end
  end

  ##
  # Provides a wrapper for interacting with the Skykick API.
  #
  class ClientWrapper
    attr_reader :api

    ##
    # Initializes the Skykick client with the given authentication credentials.
    #  # use userid and primary key for login information found in https://portal.skykick.com/partner/admin/user-profile
    #
    # @param [String] client_id The client ID used for authentication.
    # @param [String] client_secret The client secret used for authentication.
    # @param [Boolean] log Whether to enable logging (default is true).
    #
    def initialize(client_id, client_secret, log = true)
      @tenants = nil
      Skykick.configure do |config|
        config.client_id = client_id
        config.client_secret = client_secret
        config.logger = Logger.new(FileUtil.daily_file_name('skykick.log')) if log
      end
      @api = Skykick.client
      @api.login
    end

    ##
    # Retrieves all tenants from the Skykick system.
    #
    # @return [Array<TenantData>] A list of all tenant objects.
    #
    def tenants
      unless @tenants
        @tenants = {}
        data = @api.subscriptions
        data.each do |item|
          @tenants[item.id] = TenantData.new(item.id, item.companyName, item.orderState, item.attributes)
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
    # Retrieves all alerts associated with a specific customer.
    #
    # @param [String, NilClass] customer_id The customer ID for which alerts are being fetched. If nil, all alerts are fetched.
    # @return [Hash] A hash of alert IDs mapped to alert objects.
    #
    def alerts(customer_id = nil)
      @alerts = {}
      data = @api.alerts(customer_id)

      # :id, :description, :severity, :category, :product, :actions
      data.each do |item|
        status = item.Status
        next unless 'Active'.eql? status

        alert = AlertData.new(
          item.Id, item.PublishDate, item.Description, item.AlertType, item.Subject, 'Skykick', item.BackupMailboxId, 'Mailbox', item.attributes
        )
        @alerts[alert.id] = alert
      end
      @alerts
    end
  end
end
