require "dotenv"
require 'zammad_api'
require_relative "utils"
require_relative 'MonitoringConfig'
require_relative 'MonitoringSLA'
require_relative 'MonitoringModel'


class TicketCheck
  FAILED = 'failed'
  SUCCEEDED = 'succeeded'
  UNKNOWN = 'unknown'
  attr_reader :match, :description

  def initialize( match_string, description, failed, succeeded )
    @match = match_string
    @description = description
    @failed_scan = failed
    @succeeded_scan = succeeded

    @reg = Regexp.new(@match)
  end

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
  
  def matches? ticket
    ticket.title.match(@reg)
  end
end

class SynologyCheck < TicketCheck
    def initialize
        super('\[.*\] Network backup - .*','Synology(NL)','mislukt','voltooid')
    end
end

class TicketMonitor < AbstractMonitor
  TWO_DAYS = 48
  STATE_CLOSED = 'closed'

	def initialize( report, config, log ) 
    client = ZammadAPI::Client.new(
        url:          ENV['ZAMMAD_HOST'] || ENV['ZAMMAN_HOST'],
        oauth2_token: ENV['ZAMMAD_OAUTH_TOKEN']
    )
		super( 'TicketScan', client, report, config, log )
    zammad_consts()
    setup_checkers()
	end

  def run
    # 1) Check all tickets in monitoring group; assume 100 is max?
    tickets = @client.ticket.search(query: "state.name:new AND group.name:#{@monitoring_group}")
    tickets.page(1,100) do |ticket|
      # check if these match a TicketCheck
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
              if (config = config_by_mail(ticket.created_by)) && (config.monitor_backup)

                ## update watchdog for last found message
                config.last_backup = DateTime.parse ticket.created_at
puts "Domain found for '#{config.description}', last backup #{config.last_backup}"
                # process succeeded/failed and move/close message
                if result == TicketCheck::FAILED
                  ## move ticket to inbox to resolve
                  move_to_inbox(ticket,'Backup failed, move ticket to inbox')
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
      # it seems not an SLA ticket
      unless match
        move_to_inbox(ticket,"* TicketMonitor no match found for subject , moved to inbox" )
      end
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

  def move_to_inbox(ticket,message)
    @report.puts "#{message} - ticket number #{ticket.number}"
    ticket.group_id = @inbox_group_id
    add_article(ticket,message)
    ticket.save
  end
  def close_ticket(ticket)
    message = "Backup succeeded, moving ticket to archive/closed"
    @report.puts "- #{message} - ticket number #{ticket.number}"
    ticket.state_id = @closed_id
    add_article(ticket,message)
    ticket.save
  end
  def add_article(ticket,text)
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
      entry = @config.entries.select{ |cfg| mail_address.eql? cfg.backup_domain.to_s.downcase}.first
    end
    entry
  end
  
  def zammad_consts
    @closed_id = @inbox_group_id = @monitoring_group_id = nil
    # read closed state id
    closed = @client.ticket_state.all.select{|state| state.name .eql? STATE_CLOSED}
    raise StandardError.new("Zammad State not found '#{STATE_CLOSED}'") unless closed.first
    @closed_id = closed.first.id
    @report.puts " State id #{STATE_CLOSED}=#{@closed_id}"


    # read group id for inbox and monitoring group where tickets come in
    @inbox_group = ENV['INBOX_GROUP'] || 'Test'
    @monitoring_group = ENV['ZAMMAD_GROUP'] || 'Monitoring'
    raise StandardError.new(" Monitoring and Inbox group cannott be the same'#{@monitoring_group}'") if @monitoring_group.eql? @inbox_group

    groups = @client.group.all
    groups.each do |group|
      if @monitoring_group.eql? group.name
        @monitoring_group_id = group.id
      elsif @inbox_group.eql? group.name
        @inbox_group_id = group.id
      end
    end
    raise StandardError.new("Zammad Monitoring group not found '#{@monitoring_group}'") unless @monitoring_group_id
    @report.puts " Monitoring group is #{@monitoring_group}=#{@monitoring_group_id}"
    raise StandardError.new("Zammad Inbox group not found '#{@inbox_group}'") unless @inbox_group_id
    @report.puts " Inbox group is #{@inbox_group}=#{@inbox_group_id}"
  end
  
  def setup_checkers
    @checkers = []
    @checkers << SynologyCheck.new
  end
end


puts "TicketMonitor v1.0 - #{Time.now}",""

# use environment from .env if any
Dotenv.load
config = MonitoringConfig.new

File.open( FileUtil.daily_file_name( "ticket-report.txt" ), "w") do |report|
  monitor = TicketMonitor.new(report,config,true)
  monitor.run
end

config.save_config

