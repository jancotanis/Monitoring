# frozen_string_literal: true

require 'dotenv'
require 'zammad_api'

require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'MonitoringSLA'
require_relative 'MonitoringModel'

class ConfigError < StandardError; end

class TicketCheck
  # Constants to represent the status of a ticket check
  FAILED = 'failed'       # Indicates the ticket has failed the check
  SUCCEEDED = 'succeeded' # Indicates the ticket has passed the check
  UNKNOWN = 'unknown'     # Indicates the ticket status is unknown

  # Read-only attributes for match string and description
  attr_reader :match, :description

  # Initializes a TicketCheck instance
  # @param match_string [String] A regex pattern to check for matches in ticket titles
  # @param description [String] Description of the check
  # @param failed [String] Substring to look for that indicates a failed scan
  # @param succeeded [String] Substring to look for that indicates a successful scan
  def initialize(match_string, description, failed, succeeded)
    @match = match_string
    @description = description
    @failed_scan = failed
    @succeeded_scan = succeeded

    # Compile the match string into a regular expression
    @reg = Regexp.new(@match)
  end

  # Tests the ticket's title for specific status indicators
  # @param ticket [Object] A ticket object with a `title` method
  # @return [String] FAILED, SUCCEEDED, or UNKNOWN based on the ticket's title
  def test(ticket)
    title  = ticket.title
    if title.include? @failed_scan
      FAILED
    elsif title.include? @succeeded_scan
      SUCCEEDED
    else
      UNKNOWN
    end
  end

  # Checks if the ticket title matches the regular expression
  # @param ticket [Object] A ticket object with a `title` method
  # @return [MatchData, nil] The match result or nil if no match
  def matches?(ticket)
    ticket.title.match(@reg)
  end
end

class SynologyCheck < TicketCheck
  # Initializes a SynologyCheck instance with predefined parameters
  def initialize
    # Call the parent class (TicketCheck) initializer with a regex pattern to match titles like
    #  "[...] Network backup - ..."
    super('\[.*\] Network backup - .*', 'Synology(NL)', 'mislukt', 'voltooid')
  end
end

class TicketMonitor < AbstractMonitor
  TWO_DAYS = 48
  STATE_CLOSED = 'closed'

  def initialize(report, config, log)
    client = ZammadAPI::Client.new(
      url:          ENV['ZAMMAD_HOST'],
      oauth2_token: ENV['ZAMMAD_OAUTH_TOKEN']
    )
    super('TicketScan', client, report, config, log)
    zammad_consts
    setup_checkers
  end

  def run
    # 1) Check all tickets in monitoring group; assume 100 is max?
    tickets = @client.ticket.search(query: "state.name:new AND group.name:#{@monitoring_group}")
    tickets.page(1, 100) do |ticket|
      # Unknown ticket type so move to inbox unless processed
      move_to_inbox(ticket, '* TicketMonitor no match found for subject, moved to inbox') unless process_ticket(ticket)
    end
    run_watchdog
  end

  def run_watchdog
    # check if backups haven't ran for 2 days.
    @config.entries.each do |cfg|
      # check  backup monitored entries
      if cfg.monitor_backup
        cfg.last_backup = DateTime.now unless cfg.last_backup
        if (DateTime.now - cfg.last_backup) * 24 > TWO_DAYS
          # only valid for backups using mail notifications so check domain
          # alert if backup_domain
puts "Didn't get any notifications for #{cfg.description} since #{cfg.last_backup}"
        end
      end
    end
  end

private

  def process_ticket(ticket)
    match = false
    @checkers.each do |check|
      # if unknown - move to inbox, add message not sure what to do with this
      # if succes/failure -> find config user
      #  update last date check
      #  if failure - move to inbox to action
      if check.matches?(ticket)
        match = true
        result = check.test(ticket)
        if result == TicketCheck::UNKNOWN
          @report.puts "* Unknown if failure/success: #{ticket.number} - #{ticket.title} - move to inbox"
        else
          @report.puts "  ticket: #{ticket.number} matches #{check.description} - #{result} - #{ticket.title}"
          ## find backup SLA
          if (config = config_by_mail(ticket.created_by)) && config.monitor_backup
            ## update watchdog for last found message
            config.last_backup = DateTime.parse(ticket.created_at)
puts "Domain found for '#{config.description}', last backup #{config.last_backup}"
            # process succeeded/failed and move/close message
            if result == TicketCheck::FAILED
              ## move ticket to inbox to resolve
              move_to_inbox(ticket, 'Backup failed, move ticket to inbox')
              match = true
            elsif result == TicketCheck::SUCCEEDED
              close_ticket(ticket)
              match = true
            end
          else
            @report.puts "* Domain not found for '#{ticket.created_by}' or no monitor_backup SLA; ticket ignored"
          end
        end
      end
    end
  end

  def move_to_inbox(ticket, message)
    @report.puts "#{message} - ticket number #{ticket.number}"
    ticket.group_id = @inbox_group_id
    add_article(ticket, message)
    ticket.save
  end

  def close_ticket(ticket)
    message = 'Backup succeeded, moving ticket to archive/closed'
    @report.puts "- #{message} - ticket number #{ticket.number}"
    ticket.state_id = @closed_id
    add_article(ticket, message)
    ticket.save
  end

  def add_article(ticket, text)
    a = ticket.article(
      type: 'note',
      subject: 'Ticket Monitoring Script',
      body: text
    )
    a.save
  end

  def config_by_mail(mail_address)
    entry = nil
    if mail_address && mail_address['@']
      mail_address = mail_address.downcase.split('@').last
      entry = @config.entries.select { |cfg| mail_address.eql? cfg.backup_domain.to_s.downcase }.first
    end
    entry
  end

  def zammad_consts
    @closed_id = @inbox_group_id = @monitoring_group_id = nil
    # read closed state id
    closed = @client.ticket_state.all.select { |state| state.name.eql? STATE_CLOSED }
    raise ConfigError, "Zammad State not found '#{STATE_CLOSED}'" unless closed.first

    @closed_id = closed.first.id
    @report.puts " State id #{STATE_CLOSED}=#{@closed_id}"

    # read group id for inbox and monitoring group where tickets come in
    @inbox_group = ENV['INBOX_GROUP'] || 'Test'
    @monitoring_group = ENV['ZAMMAD_GROUP'] || 'Monitoring'
    raise ConfigError, "Monitoring and Inbox group cannot be the same'#{@monitoring_group}'" if @monitoring_group.eql? @inbox_group

    group_ids
  end
  
  def group_ids
    groups = @client.group.all
    groups.each do |group|
      if @monitoring_group.eql? group.name
        @monitoring_group_id = group.id
      elsif @inbox_group.eql? group.name
        @inbox_group_id = group.id
      end
    end
    raise ConfigError, "Zammad Monitoring group not found '#{@monitoring_group}'" unless @monitoring_group_id

    @report.puts " Monitoring group is #{@monitoring_group}=#{@monitoring_group_id}"
    raise ConfigError, "Zammad Inbox group not found '#{@inbox_group}'" unless @inbox_group_id

    @report.puts " Inbox group is #{@inbox_group}=#{@inbox_group_id}"
  end

  def setup_checkers
    @checkers = []
    @checkers << SynologyCheck.new
  end
end

puts "TicketMonitor v1.0 - #{Time.now}", ''

# use environment from .env if any
Dotenv.load
config = MonitoringConfig.new

File.open(FileUtil.daily_file_name('ticket-report.txt'), 'w') do |report|
  monitor = TicketMonitor.new(report, config, true)
  monitor.run
end

config.save_config
