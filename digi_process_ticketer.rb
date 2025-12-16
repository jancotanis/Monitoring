# frozen_string_literal: true
require 'logger'
require 'faraday'

# Ticketer is a class that creates tickets in DigiProcess via the hooks API.
class DigiProcessTicketer
  TICKET_SOURCE = 'Monitor Script'
  TICKET_TYPE = 'Storing A'
  TICKET_STATUS = 'Aangemaakt'
  PRIO_NORMAL = nil
  attr_reader :client

  # Initializes a new Ticketer instance.
  #
  # @param options [Hash] Options for configuring the client, such as a logger.
  def initialize(options)
    @secret         = ENV.fetch('DIGIPROCESS_SECRET')
    @web_hook       = ENV.fetch('DIGIPROCESS_WEBHOOK')
    @source         = ENV.fetch('DIGIPROCESS_SOURCE')
    @customer_id    = ENV.fetch('DIGIPROCESS_RELATION_NUMBER')        # The customer associated with tickets
    @customer_email = ENV.fetch('DIGIPROCESS_RELATION_EMAIL')         # The customer associated with tickets
    setup_connection
    @debug = 'DEBUG'.eql? ENV.fetch('MONITORING')    # Enable debug mode
    @logger = options[:log]
  end

  # Creates a new ticket in Zammad.
  #
  # @param title [String] The title of the ticket.
  # @param text [String] The body text of the ticket.
  # @param ticket_prio [String] (optional) The priority of the ticket (default: PRIO_NORMAL).
  # @param ticket_type [String, nil] (optional) A tag to categorize the ticket.
  # @return [ZammadAPI::Object, nil] The created ticket object, or nil if in debug mode.
  def create_ticket(title, text, ticket_prio = PRIO_NORMAL, ticket_type = nil)
    ticket = nil
    unless @debug
      # ticket_prio, ticket group, customer hardcoded?
      content = {
        relation_number: @customer_id,
        relation_email: @customer_email,
        ticket_type: ticket_type,
#        ticket_source: TICKET_SOURCE,
#        ticket_status: TICKET_STATUS, - use default
        title: title,
        description: text
      }
puts content.to_json 
      ticket = @connection.post('', content)
    end
    ticket
  end
  
  def setup_connection()
    @connection = Faraday::Connection.new(url: "https://erp.digi-process.nl/webhook_gateway_integrations/delegate/#{@web_hook}") do |connection|
      connection.use Faraday::Response::RaiseError
      connection.adapter Faraday.default_adapter
      connection.headers['DPE-Webhook-Secret'] = @secret if @secret
      connection.response :json, content_type: /\bjson$/
      connection.use Faraday::Request::UrlEncoded
      setup_logger(connection, @logger) if @logger
#      connection.use WrAPI::RateThrottleMiddleware, limit: rate_limit, period: rate_period if rate_limit && rate_period
    end
  end
  
  def setup_logger(connection, logger)
    connection.response :logger, logger, { headers: true, bodies: true } do |log|
      # Filter sensitive information from JSON content, such as passwords and access tokens.
      # log.filter(/("DPE-Webhook-Secret":")(.+?)(".*)/, '\1[REMOVED]\3')
    end
  end

end
