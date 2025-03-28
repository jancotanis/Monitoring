# frozen_string_literal: true

require 'integra365'
require 'logger'

require_relative 'utils'
require_relative 'MonitoringModel'

##
# The Integra365 module provides integration with the Integra365 backup and alerting system.
# It defines structures for handling tenant data, endpoints, and alerts related to backups.
#
module Integra365
  ##
  # Represents a tenant in the Integra365 system.
  #
  # @attr [String] id The tenant ID.
  # @attr [String] name The name of the tenant.
  # @attr [Hash] raw_data Additional data related to the tenant.
  # @attr [Hash] endpoints A hash of endpoints associated with the tenant.
  # @attr [Array] alerts A list of alerts associated with the tenant.
  #
  TenantData = Struct.new(:id, :name, :raw_data, :endpoints, :alerts) do
    include MonitoringTenant

    ##
    # Initializes a new tenant instance.
    #
    # @param [String] id The tenant ID.
    # @param [String] name The tenant's name.
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
  # Represents an endpoint in the Integra365 system.
  #
  class EndpointData < MonitoringEndpoint; end

  ##
  # Represents an alert in the Integra365 system.
  #
  # @attr [String] id The alert ID.
  # @attr [Time] created The time the alert was created.
  # @attr [String] description The alert's description.
  # @attr [String] severity The severity level of the alert.
  # @attr [String] category The category of the alert.
  # @attr [String] product The associated product.
  # @attr [String] endpoint_id The endpoint ID related to the alert.
  # @attr [String] endpoint_type The type of the endpoint related to the alert.
  # @attr [String] tenant_id The ID of the tenant associated with the alert.
  # @attr [Hash] raw_data Additional data related to the alert.
  #
  AlertData = Struct.new(:id, :created, :description, :severity, :category,
                         :product, :endpoint_id, :endpoint_type, :tenant_id, :raw_data) do
    include MonitoringAlert

    ##
    # Creates a new endpoint associated with the alert.
    #
    # @return [Integra365::EndpointData] A new endpoint created for the alert.
    #
    def create_endpoint
      # endpoint is a backup job
      Integra365::EndpointData.new(id, 'BackupJob', property('jobName').to_s)
    end
  end

  ##
  # Provides a wrapper for interacting with the Integra365 API.
  #
  class ClientWrapper
    attr_reader :api

    ##
    # Initializes the Integra365 client with the given user credentials.
    #
    # @param [String] user The username for authentication.
    # @param [String] password The password for authentication.
    # @param [Boolean] log Whether to enable logging (default is true).
    #
    def initialize(user, password, log = true)
      @tenants = nil
      Integra365.configure do |config|
        config.username = user
        config.password = password
        config.logger = Logger.new(FileUtil.daily_file_name('integra365.log')) if log
      end
      @api = Integra365.client
      @api.login
    end

    ##
    # Retrieves all tenants from the Integra365 system.
    #
    # @return [Array<TenantData>] A list of all tenant objects.
    #
    def tenants
      unless @tenants
        @tenants = {}
        data = @api.tenants
        data.each do |item|
          # use tenant name as ID since it's present in job reporting
          @tenants[item.tenantName] = TenantData.new(item.tenantName, item.friendlyName, item.attributes)
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
    # @param [String, NilClass] customer_id The customer ID for which alerts are being fetched.
    #                           If nil, all alerts are fetched.
    # @return [Hash] A hash of alert IDs mapped to alert objects.
    #
    def alerts(customer_id = nil)
      # API returns all job statuses for all customers, so load once
      unless @all_alerts
        @all_alerts = {}

        data = @api.backup_job_reporting
        data.each do |item|
          # make alerts unique by adding incident datetime
          id = "#{item.organization}:#{item.lastRun}"
          # actual error/warning is under session link for the backup job
          description = "#{item.jobName}\n please check session under backup jobs for a detailed description (https://office365.integra-bcs.nl/backup/index)."
          # :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :tenant_id, :raw_data
          alert = AlertData.new(id, item.lastRun, description, item.lastStatus, 'Job', 'Integra365', id, 'BackupJob', item.organization, item.attributes)
          @all_alerts[alert.id] = alert
        end
      end

      @alerts = @all_alerts.select { |_k, alert| customer_id.nil? || alert.tenant_id.eql?(customer_id) }
    end
  end
end
