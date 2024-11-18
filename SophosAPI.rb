# frozen_string_literal: true

require 'logger'
require 'sophos_central_api'

require_relative 'utils'
require_relative 'MonitoringModel'

module Sophos
  TenantData = Struct.new(:id, :name, :api, :status, :billing_type, :raw_data, :endpoints, :alerts) do
    def initialize(*)
      super
      self.endpoints ||= {}
      self.alerts ||= []
    end

    def trial?
      'trial'.eql?(billing_type)
    end

    def description
      # it looks like new tenants are created as COAS Business Systems and showAs is the actual name.
      name
    end

    def apiHost
      api
    end

    def clear_endpoint_alerts
      endpoints&.each do |_k, v|
        v.clear_alerts
      end
    end

    def lazy_endpoints_loader(loader)
      self[:endpoints] = nil
      define_singleton_method(:endpoints) do
        self[:endpoints] ||= loader.call
        self[:endpoints]
      end
    end
  end

  class EndpointData < MonitoringEndpoint; end

  AlertData = Struct.new(:id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data) do
    def create_endpoint
      Sophos::EndpointData.new(endpoint_id, property('managedAgent.type') + '/' + property('product'), property('managedAgent.name'))
    end
  end

  class ClientWrapper
    attr_reader :api

    def initialize(client_id, client_secret, log = true)
      Sophos.configure do |config|
        config.client_id = client_id
        config.client_secret = client_secret
        config.logger = Logger.new(FileUtil.daily_file_name('sophos.log')) if log
      end
      @api = Sophos.client
      @api.login
    end

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

    def tenant_by_id(id)
      tenants unless @tenants
      @tenants[id]
    end

    def endpoints(customer)
      endp = {}
      data = @api.client(customer).endpoints
      data.each do |item|
        status = item.health.overall if item.attributes.key? 'health'
        group_name = item.group.name if item.attributes.key? 'group'
        endp[item.id] = EndpointData.new(item.id, item.type, item.hostname, group_name, status, item.attributes)
      end
      endp
    rescue => e
      @logger&.error e
      @logger&.error e.response.to_json
    end

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
