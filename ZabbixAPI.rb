# frozen_string_literal: true

require 'logger'
require 'zabbix_api_gem'

require_relative 'utils'
require_relative 'MonitoringModel'

module Zabbix
  TenantData = Struct.new(:id, :name, :status, :raw_data, :endpoints, :alerts) do
    include MonitoringTenant

    def initialize(*)
      super
      self.alerts ||= []
    end

    def lazy_endpoints_loader(loader)
      self[:endpoints] = nil
      define_singleton_method(:endpoints) do
        self[:endpoints] ||= loader.call
      end
    end
  end

  class EndpointData < MonitoringEndpoint; end

  AlertData = Struct.new(:id, :created, :description, :severity_code, :category, :product, :endpoint_id, :endpoint_type, :raw_data, :event) do
    def create_endpoint
      # :id, :type, :hostname, :tenant, :status, :raw_data
      Zabbix::EndpointData.new(id, '?', '?')
    end

    def severity
      severity_text = ['not classified', 'information', 'warning', 'average', 'high', 'disaster']
      if (severity_code.to_i >= 0) && (severity_code.to_i < severity_text.count)
        severity_text[severity_code.to_i]
      else
        severity_code
      end
    end
  end

  class ClientWrapper
    attr_reader :api

    # use userid and primary key for login information found in https://zabbix-portal/zabbix.php?action=token.list
    def initialize(host, auth_token, log = true)
      Zabbix.configure do |config|
        config.endpoint = host
        config.access_token = auth_token
        config.logger = Logger.new(FileUtil.daily_file_name('zabbix.log')) if log
      end
      @api = Zabbix.client
      @api.login
    end

    def tenants
      unless @tenants
        @tenants = {}

        data = @api.hostgroups
        data.each do |item|
          t = TenantData.new(item.groupid, item.name, nil, item.attributes)
          @tenants[t.id] = t
          # lazy loading
          t.lazy_endpoints_loader(-> { endpoints(t) })
        end
      end
      @tenants.values
    end

    def endpoints(customer)
      endp = {}

      data = @api.hosts({ groupids: [customer.id], output: 'extend', selectInventory: 'extend' })
      # :id, :type, :hostname, :group, :status, :raw_data, :alerts, :incident_alerts
      data.each do |item|
        e = endp[item.hostid] = EndpointData.new(item.hostid, 'zabbix item', item.name, customer.id, item.status, item.attributes)
        type = e.property('inventory.type')
        e.type = type unless type.to_s.empty?
      end
      endp
    end

    def alerts(customer = nil)
      @alerts = {}

      query = nil
      query = { groupids: [customer.id] } if customer
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
          puts "* host #{a.endpoint_id} in multiple zabbix groups" if event.hosts.count > 1
        end
        @alerts[a.id] = a
      end
      @alerts
    end

    private

    def events_by_id(id)
      id = [id] unless id.is_a? Array
      # get events including hostid for the object that created the event
      @api.event(id, { selectHosts: ['hostid'] })
    end
  end
end
