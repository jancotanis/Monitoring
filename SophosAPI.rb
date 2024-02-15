require 'logger'
require 'sophos_central_api'
require_relative 'utils'

module Sophos
	# billing type - term, trial, usage
  TenantData  = Struct.new( :id, :name, :api, :status, :billing_type, :raw_data, :endpoints, :alerts ) do
    def initialize(*)
      super
      self.endpoints ||= {}
      self.alerts ||= []
    end
    
    def is_trial?
      "trial".eql?( billing_type )
    end

    def description
      # it looks like new tenants are created as COAS Business Systems and showAs is the actual name.
      name
    end

    def clear_endpoint_alerts
      if self.endpoints
        endpoints.each do |k,v|
          v.clear_alerts
        end
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

  AlertData  = Struct.new( :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data ) do
    def create_endpoint
      Sophos::EndpointData.new( endpoint_id, self.property( "managedAgent.type" ) + "/" + self.property( "product" ), self.property( "managedAgent.name" ) )
    end
  end

  class ClientWrapper
    attr_reader :api

    def initialize( client_id, client_secret, log=true )
      Sophos.configure do |config|
        config.client_id = client_id
        config.client_secret = client_secret
        config.logger = Logger.new( FileUtil.daily_file_name( "sophos.log" ) ) if log
      end
      @api = Sophos.client
      @api.login
    end

    def tenants
      if !@tenants
        @tenants = {}
        data = @api.tenants
        data.each do |item|
          t = TenantData.new( item.id, item.showAs, item.apiHost, item.status, item.billingType, item.attributes )
          @tenants[ t.id ] = t
          endpoints = YAML.load_file( cache_file( t ) ) if File.file?( cache_file( t ) )
          if !endpoints
            endpoints = @api.endpoints( t ) || {}
            update_cache( t ) 
          end
          t.endpoints = endpoints
        end
      end
      @tenants.values
    end

    def tenant_by_id( id )
      tenants if !@tenants
      @tenants[ id ]
    end

    def endpoints( customer )
      @endpoints={}

      data = @api.client(customer).endpoints
      data.each do |item|
        status = item.health.overall if item.health
        ep = EndpointData.new( item.id, item.type, item.hostname, item.groupName, status, item.attributes )
        @endpoints[ ep.id ] = ep
      end
      @endpoints
    rescue => e
      @logger.error e if @logger
      @logger.error e.response.to_json if @logger
    end

    def alerts( customer )
      @alerts={}

      data = @api.client(customer).alerts
      data.each do |item|
        a = AlertData.new( item.id, item.raisedAt, item.description, item.severity, item.category, item.product, item.managedAgent.id, item.managedAgent.type, item.attributes )
        @alerts[ a.id ] = a
      end
      @alerts
    end

    def siem( customer )
      @alerts={}

      data = @api.client(customer).get( "/siem/v1/alerts" )
      #:id, :description, :severity, :category, :product, :actions
      data.each do |item|
        a = AlertData.new( item.id, item.when, item.description, item.severity, item.category, item.product, item.data.endpoint_id, item.data.endpoint_type, item.attributes )
        @alerts[ a.id ] = a
      end
      @alerts
    end
  end
end
