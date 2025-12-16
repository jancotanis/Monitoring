# frozen_string_literal: true
require 'logger'
require 'faraday'
require_relative 'utils'

# Ticketer is a class that creates tickets in DigiProcess via the hooks API.
class DigiProcessTicketer
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
    @customer_id    = ENV['DIGIPROCESS_RELATION_NUMBER']        # The customer associated with tickets
    @customer_email = ENV['DIGIPROCESS_RELATION_EMAIL']         # The customer associated with tickets
    @logger = Logger.new(FileUtil.daily_file_name('digi_process.log')) if options[:log]
    setup_connection
    @debug = 'DEBUG'.eql? ENV.fetch('MONITORING')    # Enable debug mode
  end

  # Creates a new ticket in Zammad.
  #
  # @param title [String] The title of the ticket.
  # @param text [String] The body text of the ticket.
  # @param ticket_prio [String] (optional) The priority of the ticket (default: PRIO_NORMAL).
  # @param ticket_type [String, nil] (optional) A tag to categorize the ticket.
  # @return The created ticket object, or nil if in debug mode.
  def create_ticket(title, text, ticket_prio = PRIO_NORMAL, ticket_type)
    ticket = nil
    unless @debug
      # ticket_prio, ticket group, customer hardcoded?
      # ticket_status: TICKET_STATUS not set so use default
      content = {
        ticket_type: ticket_type,
        ticket_source: @source,
        title: title,
        description: text
      }
      content[:relation_number] = @customer_id if @customer_id
      content[:relation_email]  = @customer_email if  @customer_email

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
      log.filter(/("DPE-Webhook-Secret":")(.+?)(".*)/, '\1[REMOVED]\3')
    end
  end

end
