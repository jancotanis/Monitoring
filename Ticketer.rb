# frozen_string_literal: true

require 'zammad_api'

# Ticketer is a class that creates tickets in Zammad via the API.
class Ticketer
  PRIO_LOW    = '1 low'
  PRIO_NORMAL = '2 normal'
  PRIO_HIGH   = '3 high'

  # Initializes a new Ticketer instance.
  #
  # @param options [Hash] Options for configuring the client, such as a logger.
  def initialize(options)
    @client = ZammadAPI::Client.new(
      url:          ENV['ZAMMAD_HOST'],       # URL of the Zammad API
      oauth2_token: ENV['ZAMMAD_OAUTH_TOKEN'], # OAuth2 token for authentication
      logger:       options[:log]             # Optional logger
    )
    @group = ENV['ZAMMAD_GROUP']               # The group to which tickets are assigned
    @customer = ENV['ZAMMAD_CUSTOMER']         # The customer associated with tickets
    @debug = 'DEBUG'.eql? ENV['MONITORING']    # Enable debug mode
  end

  # Creates a new ticket in Zammad.
  #
  # @param title [String] The title of the ticket.
  # @param text [String] The body text of the ticket.
  # @param ticket_prio [String] (optional) The priority of the ticket (default: PRIO_NORMAL).
  # @param ticket_tag [String, nil] (optional) A tag to categorize the ticket.
  # @return [ZammadAPI::Object, nil] The created ticket object, or nil if in debug mode.
  def create_ticket(title, text, ticket_prio = PRIO_NORMAL, ticket_tag = nil)
    ticket = nil
    unless @debug
      ticket = @client.ticket.create(
        title: title,
        state: 'new',
        group: @group,
        priority: ticket_prio,
        customer: @customer,
        article: {
          content_type: 'text/plain', # or text/html, if not given, text/plain is used
          body: text
        },
        tags: "monitor-script,#{ticket_tag}"
      )
    end
    puts "Ticket created: #{title}/#{ticket_prio}"
    puts text
    ticket
  end
end
