# frozen_string_literal: true

require 'json'
require 'logger'
require 'veeam'

require_relative 'utils'
require_relative 'MonitoringModel'

module Veeam
  TenantData = Struct.new(:id, :name, :status, :billing_type, :raw_data, :endpoints, :alerts) do
    def initialize(*)
      super
      self.endpoints ||= {}
      self.alerts ||= []
    end

    def description
      # it looks like new tenants are created as COAS Business Systems and showAs is the actual name.
      name
    end

    def clear_endpoint_alerts
      endpoints&.each do |_k, v|
        v.clear_alerts
      end
    end
  end

  class EndpointData < MonitoringEndpoint; end

  AlertData = Struct.new(:id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data, :company) do
    def create_endpoint
      Veeam::EndpointData.new(endpoint_id, property('object.type'), property('object.computerName') + '/' + property('object.objectName'))
    end
  end

  class ClientWrapper
    attr_reader :api

    def initialize(host, auth_token, log = true)
      Veeam.configure do |config|
        config.endpoint = host
        config.access_token = auth_token
        config.logger = Logger.new(FileUtil.daily_file_name('veeam.log')) if log
      end
      @api = Veeam.client
      @api.login
    end

    # get alla customers
    def tenants
      unless @tenants
        @tenants = {}

        data = @api.companies
        data.each do |item|
          t = TenantData.new(item.instanceUid, item.name, item.status, item.subscriptionPlanUid, item.attributes)
          @tenants[t.id] = t
        end
      end
      @tenants.values
    end

    def endpoints
      unless @endpoints
        @endpoints = []

        data = @api.backup_servers
        data.each do |item|
          @endpoints << EndpointData.new(item.instanceUid, item.backupServerRoleType, item.name, item.organizationUid, item.status, item.attributes)
        end
      end
      @endpoints
    rescue => e
      @logger&.error e
      @logger&.error e.response.to_json
    end

    def alerts
      @alerts = {}

      data = @api.active_alarms
      data.each do |item|
        la = item.lastActivation
        o = item.object
        a = AlertData.new(item.instanceUid, la.time, la.message.strip, la.status, o.type, 'veeam', o.objectUid, o.type, item.attributes)
        @alerts[a.id] = a
      end
      @alerts
    end
  end
end
