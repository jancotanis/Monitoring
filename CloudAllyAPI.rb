require 'cloudally'
require 'logger'

require_relative 'utils'

module CloudAlly
  # Tenant data wrapper around users
	# billing type - term, trial, usage
  STATUS_WANTED = "FAILED"
  
  TenantData  = Struct.new( :id, :name, :status, :billing_type, :raw_data, :endpoints, :alerts ) do
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
  # Endpoint data wrapper around tasks
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
  # Alert data wrapper for task statusses
  AlertData  = Struct.new( :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data ) do
    def description
      # collect subsources that failed the task
      failedSubSources = raw_data["backupStatus"].select{ |src| STATUS_WANTED.eql? src.status }.map{ |o| o.subSource }.join ' '
      "#{endpoint_type}: #{failedSubSources}"
    end
    def create_endpoint
      CloudAlly::EndpointData.new( endpoint_id, category, endpoint_type )
    end
  end

  class ClientWrapper
    attr_reader :api

    def initialize( client_id, client_secret, user, password, log=true )
      #silent logger  Logger.new(IO::NULL)
      CloudAlly.configure do |config|
        config.client_id = client_id
        config.client_secret = client_secret
        config.username = user
        config.password = password
        config.logger = Logger.new( FileUtil.daily_file_name( "cloudally.log" ) ) if log
      end
      CloudAlly.partner_login
      @api = CloudAlly.client
    end

    def tenants
      if !@tenants
        @tenants = {}
        data = @api.partner_users
        data.each do |item|
          t = TenantData.new( item.id, item.name, item.status, item.discount.to_s, item.attributes )
          @tenants[ t.id ] = t
        end
      end
      @tenants.values
    end
    def tenant_by_id( id )
      tenants if !@tenants
      @tenants[ id ]
    end
    def endpoints( tenant )
      @endpoints = get_endpoints() unless @endpoints
      @endpoints.values.select { |e| tenant.eql?( e.tenant ) }
    end

    def alerts( tenant=nil )
      @alerts = get_alerts() unless @alerts
      if tenant
        @alerts.values.select{ |a| tenant.eql?( a.property("userId") ) }
      else
        @alerts.values
      end
    end
  private

     def get_endpoints()
      @endpoints={}
      data = @api.partner_tasks
      data.each do |item|
        @endpoints[ item.id ] = EndpointData.new( item.id, item.type + '/' + item.source, item.alias, item.userId, item.status, item.attributes )
      end
      @endpoints
    end

    def get_alerts()
      @alerts={}
      alert_id = 0
      data = @api.partner_status
      data.each do |item|
        alert_id += 1
        a = create_alert_from_data( alert_id, item )
        @alerts[ alert_id ] = a if a
      end
      @alerts
    end
    # filter alerts for STATUS wanted
    def create_alert_from_data alert_id, item
        not_actives = item.backupStatus.select { |si| STATUS_WANTED.eql?( si.status ) }
        a = AlertData.new( alert_id, item.lastBackupAttemptDate, not_actives.first.error, not_actives.first.status, item.source, item.source, item.taskId, item.entityName, item.attributes ) if not_actives.count > 0
    end
  end
end
