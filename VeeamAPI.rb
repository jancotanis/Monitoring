# frozen_string_literal: true

require 'json'
require 'logger'
require 'veeam'

require_relative 'utils'
require_relative 'MonitoringModel'

##
# The Veeam module provides integration with the Veeam backup and monitoring system.
# It defines structures for handling tenant data, endpoints, and alerts.
#
module Veeam
  ##
  # Represents a tenant in the Veeam system.
  #
  # @attr [String] id The tenant ID.
  # @attr [String] name The tenant name.
  # @attr [String] status The tenant's current status.
  # @attr [String] billing_type The billing type associated with the tenant.
  # @attr [Hash] raw_data Additional attributes related to the tenant.
  # @attr [Hash] endpoints A hash of endpoints associated with the tenant.
  # @attr [Array] alerts The list of alerts associated with the tenant.
  #
  TenantData = Struct.new(:id, :name, :status, :billing_type, :raw_data, :endpoints, :alerts) do
    include MonitoringTenant

    ##
    # Initializes a new tenant instance.
    #
    # @param [String] id The tenant ID.
    # @param [String] name The tenant name.
    # @param [String] status The tenant status.
    # @param [String] billing_type The billing type of the tenant.
    # @param [Hash] raw_data Additional attributes.
    # @param [Hash] endpoints Endpoints associated with the tenant.
    # @param [Array] alerts A list of alerts associated with the tenant.
    #
    def initialize(*)
      super
      self.endpoints ||= {}
      self.alerts ||= []
    end
  end

  ##
  # Represents an endpoint in the Veeam system.
  #
  class EndpointData < MonitoringEndpoint; end

  ##
  # Represents an alert in the Veeam system.
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
  # @attr [Object] company The company information related to the alert.
  #
  AlertData = Struct.new(:id, :created, :description, :severity, :category,
                         :product, :endpoint_id, :endpoint_type, :raw_data, :company) do
    include MonitoringAlert

    ##
    # Creates a new endpoint associated with the alert.
    #
    # @return [Veeam::EndpointData] A new endpoint created for the alert.
    #
    def create_endpoint
      Veeam::EndpointData.new(endpoint_id, property('object.type'),
                              "#{property('object.computerName')}/#{property('object.objectName')}")
    end
  end

  ##
  # Provides a wrapper for the Veeam API.
  #
  class ClientWrapper
    attr_reader :api

    ##
    # Initializes the Veeam client with authentication.
    #
    # @param [String] host The Veeam server URL.
    # @param [String] auth_token The authentication token.
    # @param [Boolean] log Whether to enable logging (default is true).
    #
    def initialize(host, auth_token, log = true)
      @tenants = nil
      Veeam.configure do |config|
        config.endpoint = host
        config.access_token = auth_token
        config.logger = Logger.new(FileUtil.daily_file_name('veeam.log')) if log
      end
      @api = Veeam.client
      @api.login
    end

    ##
    # Retrieves all tenants from Veeam.
    #
    # @return [Array<TenantData>] A list of all tenant objects.
    #
    def tenants
      unless @tenants
        @tenants = {}

        data = @api.companies
        data.each do |item|
          @tenants[item.instanceUid] = TenantData.new(item.instanceUid, item.name, item.status, item.subscriptionPlanUid, item.attributes)
        end
      end
      @tenants.values
    end

    ##
    # Retrieves all endpoints in the Veeam system.
    #
    # @return [Array<EndpointData>] A list of all endpoint objects.
    # @raise [Veeam::VeeamError] In case of any errors encountered while fetching endpoints.
    #
    def endpoints
      unless @endpoints
        @endpoints = []

        data = @api.backup_servers
        data.each do |item|
          @endpoints << EndpointData.new(item.instanceUid, item.backupServerRoleType, item.name, item.organizationUid, item.status, item.attributes)
        end
      end
      @endpoints
    rescue Veeam::VeeamError => ex
      @logger&.error ex
      @logger&.error ex.response.to_json
    end

    ##
    # Retrieves all active alerts from Veeam.
    #
    # @return [Hash] A hash of alert IDs mapped to alert objects.
    #
    def alerts
      @alerts = {}

      data = @api.active_alarms
      data.each do |item|
        la = item.lastActivation
        obj = item.object
        alert = AlertData.new(item.instanceUid, la.time, la.message.strip, la.status, obj.type, 'veeam', obj.objectUid, obj.type, item.attributes)
        @alerts[alert.id] = alert
      end
      @alerts
    end
  end
end
