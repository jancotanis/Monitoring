
class ApiBase
	def initialize( client )
		@client = client
	end

	def authorize( conn )
		conn.request :authorization, 'Bearer', @client.connection.bearer_id
#		conn.request.headers['Ocp-Apim-Subscription-Key'] = @client.connection.subscription_id
	end
	def authorize_request( req )
		req.headers['Ocp-Apim-Subscription-Key'] = @client.connection.subscription_id
	end
end
