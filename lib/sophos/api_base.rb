
class ApiBase
  def initialize( client )
    @client = client
  end

  def authorize( conn )
#	conn.request :authorization, 'Bearer', @client.connection.bearer_id
  end
end
