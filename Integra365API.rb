require 'integra365'
require 'logger'

require_relative 'utils'


module Integra365
	# billing type - term, trial, usage
  TenantData  = Struct.new( :id, :name, :raw_data, :endpoints, :alerts ) do
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
	EndpointData = Struct.new( :id, :type, :hostname, :tenant, :status, :raw_data, :alerts, :incident_alerts ) do
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
  AlertData  = Struct.new( :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :tenant_id, :raw_data ) do
    def create_endpoint
      # endpoint is backup job
      Integra365::EndpointData.new( id, "BackupJob", self.property( "jobName" ).to_s )
    end
  end

  class ClientWrapper
    attr_reader :api

    def initialize( user, password, log=true )

      Integra365.configure do |config|
        config.username = user
        config.password = password
        config.logger = Logger.new( FileUtil.daily_file_name( "integra365.log" ) ) if log
      end
      @api = Integra365.client
      @api.login
    end

    def tenants
      if !@tenants
        @tenants = {}
        data = @api.tenants
        data.each do |item|
          # use tennat name as id as this is present in job reporting
          t = TenantData.new( item.tenantName, item.friendlyName, item.attributes )
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
      # api returns all jobs statuses for all customers so load once
      if !@all_alerts
        @all_alerts = {}

        data = @api.backup_job_reporting
        data.each do |item|
          # make alerts unique bij adding incident datetime
          id = item.organization + ':' + item.lastRun
          # actual error/warning is under session link for the backup job
          description = item.jobName + "\n please check session under backup jobs for a detailed description (https://office365.integra-bcs.nl/backup/index)."
          #:id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :tenant_id, :raw_data
          a = AlertData.new( id, item.lastRun, description, item.lastStatus, 'Job', 'Integra365', id, 'BackupJob', item.organization, item.attributes )
          @all_alerts[ a.id ] = a
        end
      end

      @alerts = @all_alerts.select{ |k,a| customer_id.nil? || a.tenant_id.eql?( customer_id )}

    end
  end
end
