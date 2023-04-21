require 'open-uri'
require 'uri'

require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

require_relative 'utils'
require_relative 'lib/skykick/connection'
require_relative 'lib/skykick/tenants'
require_relative 'lib/skykick/alerts'

module Skykick
  class Client
    extend Forwardable
    attr_reader :connection
    def_delegators :@tenants, :tenants, :tenant_by_id
    def_delegators :@alerts, :alerts
    def_delegators :@connection, :create_connection

	# use userid and primary key for login information found in https://portal.skykick.com/partner/admin/user-profile
    def initialize( login, password, log=true )
	  logger = Logger.new( FileUtil.daily_file_name( "skykick.log" ) ) if log
      @connection = Connection.new( login, password, logger )
      @tenants = Tenants.new( self )
      @alerts = Alerts.new( self )
    end
  end
end
