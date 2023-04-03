require 'open-uri'
require 'uri'

require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

require_relative 'utils'
require_relative 'lib/cloudally/connection'
require_relative 'lib/cloudally/tenants'
require_relative 'lib/cloudally/endpoints'
require_relative 'lib/cloudally/alerts'

module CloudAlly
  class Client
    extend Forwardable
    attr_reader :connection
    def_delegators :@alerts, :alerts
    def_delegators :@tenants, :tenants
    def_delegators :@endpoints, :endpoints
    def_delegators :@connection, :create_connection

    def initialize( client_id, client_secret, user, password, log=true )
	  #silent logger  Logger.new(IO::NULL)
	  logger = Logger.new( FileUtil.daily_file_name( "cloudally.log" ) ) if log
      @connection = Connection.new( client_id, client_secret, user, password, logger )
      @tenants = Tenants.new( self )
      @endpoints = Endpoints.new( self )
      @alerts = Alerts.new( self )
    end
  end
end
