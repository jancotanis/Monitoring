require 'date'
class ApiBase
	def initialize( client )
		@client = client
	end
	def create_request( method, params=nil )
		result = {
			"jsonrpc": "2.0",
			"method": method,
			"params": {
				"output": "extend"
			},
			"id": 1
		}

		if params
			params.each do |k,v|
				result[:params][k] = v
			end
		end
		result
	end
	
	def zabbix_clock secs
		Time.at( secs.to_i ).to_datetime
	end
end
