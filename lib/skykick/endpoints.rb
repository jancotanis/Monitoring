require 'json'
require_relative 'api_base'

module Skykick
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
end
