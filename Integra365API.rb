require 'open-uri'
require 'uri'

require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

require_relative 'utils'
require_relative 'lib/integra365/connection'
require_relative 'lib/integra365/tenants'
require_relative 'lib/integra365/alerts'

module Integra365
  class Client
    extend Forwardable
    attr_reader :connection
    def_delegators :@alerts, :alerts
    def_delegators :@tenants, :tenants
    def_delegators :@connection, :create_connection

    def initialize( user, password, log=true )
	  logger = Logger.new( FileUtil.daily_module_name( self ) ) if log
      @connection = Connection.new( user, password, logger )
      @tenants = Tenants.new( self )
      @alerts = Alerts.new( self )
    end
  end
end

