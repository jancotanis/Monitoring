require 'skykick'
require 'logger'

require_relative 'utils'

module Skykick
  TenantData  = Struct.new( :id, :name, :status, :raw_data, :endpoints, :alerts ) do
    def initialize(*)
      super
      self.endpoints ||= {}
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
  end
	EndpointData  = Struct.new( :id, :type, :hostname, :tenant, :status, :raw_data, :alerts, :incident_alerts ) do
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
      Skykick::EndpointData.new( endpoint_id, "BackupService", self.property( "BackupMailboxId" ).to_s )
    end
  end

  class ClientWrapper
    attr_reader :api

    # use userid and primary key for login information found in https://portal.skykick.com/partner/admin/user-profile
    def initialize( client_id, client_secret, log=true )
      logger = Logger.new( FileUtil.daily_file_name( "skykick.log" ) ) if log
      Skykick.configure do |config|
        config.client_id = client_id
        config.client_secret = client_secret
        config.logger = Logger.new( FileUtil.daily_file_name( "skykick.log" ) ) if log
      end
      @api = Skykick.client
      @api.login
    end

    def tenants
      if !@tenants
        @tenants = {}
        data = @api.subscriptions
        data.each do |item|
          t = TenantData.new( item.id, item.companyName, item.orderState, item.attributes )
          @tenants[ t.id ] = t
        end
      end
      @tenants.values
    end

    def tenant_by_id( id )
      tenants if !@tenants
      @tenants[ id ]
    end
    def alerts( customer_id=nil )
      @alerts = {}
      data = @api.alerts(customer_id)
      #:id, :description, :severity, :category, :product, :actions
      data.each do |item|
        status = item.Status
        if "Active".eql? status
          a = AlertData.new( item.Id, item.PublishDate, item.Description, item.AlertType, item.Subject, "Skykick", item.BackupMailboxId, "Mailbox", item.attributes )
          @alerts[ a.id ] = a
        end
      end
      @alerts
    end
  end
end
