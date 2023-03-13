require 'open-uri'
require 'uri'

require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

require_relative 'utils'
require_relative 'lib/veeam/connection'
require_relative 'lib/veeam/tenants'
require_relative 'lib/veeam/endpoints'
require_relative 'lib/veeam/alerts'

module Veeam
  class Client
    extend Forwardable
    attr_reader :connection
    def_delegators :@alerts, :alerts
    def_delegators :@tenants, :tenants
    def_delegators :@endpoints, :endpoints
    def_delegators :@connection, :create_connection

    def initialize( host, auth_token, log=true )
	  logger = Logger.new( FileUtil.daily_file_name( "veeam.log" ) ) if log
      @connection = Connection.new( host, auth_token, logger )
      @tenants = Tenants.new( self )
      @endpoints = Endpoints.new( self )
      @alerts = Alerts.new( self )
    end
  end
end
