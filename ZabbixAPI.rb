require 'logger'
require 'zabbix_api_gem'

require_relative 'utils'

module Zabbix
  TenantData  = Struct.new( :id, :name, :status, :raw_data, :endpoints, :alerts ) do
    def initialize(*)
      super
      self.alerts ||= []
    end
    
    def description
      name
    end

    def clear_endpoint_alerts
      if self.endpoints
        endpoints.each do |k,v|
          v.clear_alerts
        end
      end
    end
    
    def set_endpoints_loader(loader)
      self[:endpoints] = nil
      define_singleton_method(:endpoints) do
        self[:endpoints] ||= loader.call
      end
    end
  end

	EndpointData  = Struct.new( :id, :type, :hostname, :group, :status, :raw_data, :alerts, :incident_alerts ) do
    def initialize(*)
        super
        self.alerts ||= []
        self.incident_alerts ||= []
    end
    def clear_alerts
      self.alerts = []
          self.incident_alerts = []
    end
    def to_s
      "#{type} #{hostname}"
    end
  end

  AlertData  = Struct.new( :id, :created, :description, :severity_code, :category, :product, :endpoint_id, :endpoint_type, :raw_data, :event ) do
    def create_endpoint
      # :id, :type, :hostname, :group, :status, :raw_data
      Zabbix::EndpointData.new( id, '?', '?' )
    end
    def severity
      severity_text = ["not classified", "information", "warning", "average", "high", "disaster"]
      if ( severity_code.to_i >= 0 ) && ( severity_code.to_i < severity_text.count )
        severity_text[ severity_code.to_i ]
      else
        severity_code
      end
    end
  end

  class ClientWrapper
    attr_reader :api

    # use userid and primary key for login information found in https://zabbix-portal/zabbix.php?action=token.list
    def initialize( host, auth_token, log=true )
      Zabbix.configure do |config|
        config.endpoint = host
        config.access_token = auth_token
        config.logger = Logger.new( FileUtil.daily_file_name( "zabbix.log" ) ) if log
      end
      @api = Zabbix.client
      @api.login
    end

    def tenants
      if !@tenants
        @tenants = {}

        data = @api.hostgroups
        data.each do |item|
          t = TenantData.new( item.groupid, item.name, nil, item.attributes )
          @tenants[ t.id ] = t
          # lazy loading
          t.set_endpoints_loader( ->{ endpoints( t ) } )
        end
      end
      @tenants.values
    end

    def endpoints( customer )
      endp = {}
      
      data = @api.hosts({ "groupids":[customer.id], "selectInventory":"extend" })
      #:id, :type, :hostname, :group, :status, :raw_data, :alerts, :incident_alerts 
      data.each do |item|
        endp[ item.hostid ] = EndpointData.new( item.hostid, "zabbix item", item.name, customer.id, item.status, item.attributes )
      end

      endp
    end

    def alerts customer=nil
      @alerts={}

      query = nil
      query = { "groupids": [customer.id] } if customer
      data = @api.problems(query)
      #:id, :created, :description, :severity_code, :category, :product, :endpoint_id, :endpoint_type, :raw_data, :event
      data.each do |item|
        a = AlertData.new( item.eventid, @api.zabbix_clock( item.clock ), item.name.strip, item.severity, item.object, 'zabbix', nil, nil, item.attributes )

        event = events_by_id( a.id ).first
        if event.hosts
          h = event.hosts.first
          a.endpoint_id = h.hostid
          puts "* host #{a.endpoint_id} in multiple zabbix groups" if event.hosts.count > 1
        end
        @alerts[ a.id ] = a
      end
      @alerts
    end
  private
    def events_by_id id
      id = [id] unless id.is_a? Array
      # get events including hostid for the object that created the event
      @api.event( id, {'selectHosts':['hostid'] })
    end

  end
end
