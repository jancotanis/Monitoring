require 'open-uri'
require 'uri'

require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

require_relative 'utils'
require_relative 'lib/sophos/connection'
require_relative 'lib/sophos/tenants'
require_relative 'lib/sophos/endpoints'
require_relative 'lib/sophos/alerts'

module Sophos
  class Client
    extend Forwardable
    attr_reader :connection
    def_delegators :@tenants, :tenants, :tenant_by_id
    def_delegators :@alerts, :alerts
    def_delegators :@endpoints, :endpoints
    def_delegators :@connection, :create_connection

    def initialize( login, password, log=true )
	  logger = Logger.new( FileUtil.daily_file_name( "sophos.log" ) ) if log
      @connection = Connection.new( login, password, logger )
      @tenants = Tenants.new( self )
      @alerts = Alerts.new( self )
      @endpoints = Endpoints.new( self )
    end
  end
end
