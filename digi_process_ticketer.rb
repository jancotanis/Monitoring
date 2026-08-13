# frozen_string_literal: true

require 'logger'
require 'faraday'
require_relative 'utils'

# Ticketer is a class that creates tickets in DigiProcess via the hooks API.
class DigiProcessTicketer
  PRIO_LOW    = 'Laag'
  PRIO_NORMAL = 'Normaal'
  PRIO_HIGH   = 'Hoog'
  TICKET_STATUS = 'Aangemaakt'
  MAX_TITLE_LENGTH = 255
  MAX_DESCRIPTION_LENGTH = 60_000
  ELLIPSIS = '...'
  attr_reader :client

  # Initializes a new Ticketer instance.
  #
  # @param options [Hash] Options for configuring the client, such as a logger.
  def initialize(options)
    @secret         = ENV.fetch('DIGIPROCESS_SECRET')
    @web_hook       = ENV.fetch('DIGIPROCESS_WEBHOOK')
    @source         = ENV.fetch('DIGIPROCESS_SOURCE')
    @customer_id    = ENV.fetch('DIGIPROCESS_RELATION_NUMBER', nil)        # The customer associated with tickets
    @customer_email = ENV.fetch('DIGIPROCESS_RELATION_EMAIL', nil)         # The customer associated with tickets
    @logger = Logger.new(FileUtil.daily_file_name('digi_process.log')) if options[:log]
    setup_connection
    @debug = 'DEBUG'.eql? ENV.fetch('MONITORING', nil) # Enable debug mode
  end

  # Creates a new ticket in Zammad.
  #
  # @param title [String] The title of the ticket.
  # @param text [String] The body text of the ticket.
  # @param ticket_prio [String] The priority of the ticket, currently not used.
  # @param ticket_type [String, nil] (optional) A tag to categorize the ticket.
  # @param ticket_template [String, nil] (optional) A ticket template to use.
  # @param relation_email [String, nil] (optional) Email address for the relation.
  # @return The created ticket object, or nil if in debug mode.
  def create_ticket(title, text, ticket_prio, ticket_type, relation_email = nil, ticket_template = nil)
    ticket = content = {
      ticket_type: ticket_type,
      ticket_source: @source,
      title: sanitize(title, MAX_TITLE_LENGTH),
      description: sanitize(text, MAX_DESCRIPTION_LENGTH)
    }
    content[:relation_number] = @customer_id if @customer_id
    email = relation_email || @customer_email
    content[:relation_email]  = email if email
    content[:ticket_template] = ticket_template if  ticket_template

    unless @debug
      # ticket_prio, ticket group, customer hardcoded?
      # ticket_status: TICKET_STATUS not set so use default
      ticket = @connection.post('', content)
    end
    puts "Ticket created: #{title}/#{ticket_prio}"
    puts text
    ticket
  end

  # Trims a string to the given maximum length, appending '...' when truncated.
  #
  # When the text is longer than `max_length`, it is cut so that the result
  # (including the trailing '...') fits within `max_length`.
  #
  # @param text [String, nil] The string to sanitize.
  # @param max_length [Integer] The maximum allowed length of the result.
  # @return [String] The sanitized string, at most `max_length` characters long.
  def sanitize(text, max_length)
    text = text.to_s
    return text if text.length <= max_length

    cut = [max_length - ELLIPSIS.length, 0].max
    "#{text[0, cut]}#{ELLIPSIS}"
  end

  def setup_connection
    @connection = Faraday::Connection.new(url: "https://erp.digi-process.nl/webhook_gateway_integrations/delegate/#{@web_hook}") do |connection|
      connection.use Faraday::Response::RaiseError
      connection.adapter Faraday.default_adapter
      connection.headers['DPE-Webhook-Secret'] = @secret if @secret
      connection.response :json, content_type: /\bjson$/
      connection.use Faraday::Request::UrlEncoded
      setup_logger(connection, @logger) if @logger
    end
  end

  def setup_logger(connection, logger)
    connection.response :logger, logger, { headers: true, bodies: true } do |log|
      # Filter sensitive information from JSON content, such as passwords and access tokens.
      log.filter(/("DPE-Webhook-Secret":")(.+?)(".*)/, '\1[REMOVED]\3')
    end
  end
end
