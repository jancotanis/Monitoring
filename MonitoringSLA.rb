# frozen_string_literal: true

require 'date'
require_relative 'MonitoringConfig'
require_relative 'monitoring_notification'

# Represents a periodical notification configuration.
# @!attribute [r] config
#   @return [Object] Configuration data for the notification.
# @!attribute [r] notification
#   @return [Notification] The associated notification.
# @!attribute [r] interval
#   @return [Interval] The interval object associated with the notification.
# @!attribute [r] description
#   @return [String] A description of the periodical notification.
PeriodicalNotification = Struct.new(:config, :notification, :interval, :description)

# MonitoringSLA manages notifications and periodic alerts for customers based on SLA configurations.
#
# @example Adding a notification
#   sla = MonitoringSLA.new(config)
#   sla.add_interval_notification('Customer A', 'Backup check', 'W', '2024-01-01')
#
# @example Loading periodic alerts
#   alerts = sla.load_periodic_alerts
#   alerts.each { |alert| puts alert.description }
#
# @example Generating a report
#   sla.report
#
class MonitoringSLA
  # Initializes the MonitoringSLA with a configuration.
  #
  # @param config [Object] The configuration object containing customer entries and notifications.
  def initialize(config)
    @config = config
  end

  # Adds a notification for a specific customer with a given interval and optional start date.
  #
  # @param customer [String] The customer name.
  # @param text [String] The notification text.
  # @param interval [String] The code representing the notification interval (e.g., 'W' for weekly).
  # @param date [String, nil] The optional start date for the notification.
  # @return [void]
  # @raise [ArgumentError] If the provided date is invalid.
  def add_interval_notification(customer, text, interval, date = nil)
    cfg = @config.by_description customer
    if cfg
      if CODES.include? interval
        d = Date.parse(date) if date && !date.empty?
        n = Notification.new(text, interval, d)
        cfg.notifications << n
        cfg.create_ticket = true
        puts "Notification added: #{n}"
        @config.save_config
      else
        puts "* '#{interval}' is not a valid interval, please use #{CODES.join(', ')}"
      end
    else
      puts "* customer '#{customer}' not found in configuration"
    end
  rescue ArgumentError # assume date parsing issue
    puts "* '#{date}' is not a valid date"
  end

  # Loads periodic alerts based on the configured notifications and intervals.
  #
  # @return [Array<PeriodicalNotification>] A list of periodic notifications that are due.
  def load_periodic_alerts
    result = []

    @config.entries.each do |cfg|
      cfg.notifications ||= []
      cfg.notifications.each do |n|
        next unless CODES.include? n.interval

        interval = INTERVALS[n.interval]
        # quarter is approx 91 days
        next unless n.triggered.nil? || interval.due?(n.triggered)

        result << PeriodicalNotification.new(cfg, n, interval, n.to_s)
        n.triggered = Date.today

        # check if once is triggered and remove it
        n.interval = CLEAR_INTERVAL if ONCE.code.eql? n.interval
      end
      cfg.notifications.delete_if { |n| n.interval == CLEAR_INTERVAL }
    end
    result
  end

  # Generates a report of all customers and their active notifications.
  #
  # @return [void]
  def report
    puts report_lines
  end

  # Generates an array of all notifications all customers and their active notifications.
  #
  # @return [String]
  def report_lines
    content = []
    @config.entries.each do |cfg|
      next unless cfg.notifications&.count&.positive?

      content.push(cfg.description)
      cfg.notifications.each do |n|
        content.push("- #{n}")
      end
    end
    content
  end
end
