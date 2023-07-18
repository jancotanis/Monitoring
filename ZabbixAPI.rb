require 'open-uri'
require 'uri'

require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

require_relative 'utils'
require_relative 'lib/zabbix/connection'
require_relative 'lib/zabbix/tenants'
require_relative 'lib/zabbix/endpoints'
require_relative 'lib/zabbix/alerts'

module Zabbix
  class Client
    extend Forwardable
    attr_reader :connection
    def_delegators :@tenants, :tenants, :groups
    def_delegators :@alerts, :alerts, :events_by_id
    def_delegators :@connection, :create_connection
	def_delegators :@endpoints, :endpoints

	# use userid and primary key for login information found in https://zabbix-portal/zabbix.php?action=token.list
    def initialize( host, auth_token, log=true )
	  logger = Logger.new( FileUtil.daily_file_name( "zabbix.log" ) ) if log
      @connection = Connection.new( host, auth_token, logger )
      @tenants = Tenants.new( self )
      @endpoints = Endpoints.new( self )
      @alerts = Alerts.new( self )
    end
  end
end
