# frozen_string_literal: true

require 'date'
require_relative 'MonitoringConfig'

# Represents a recurring time interval with a description and a number of days.
# @!attribute [r] description
#   @return [String] The name of the interval.
# @!attribute [r] days
#   @return [Integer] The number of days associated with the interval.
Interval = Struct.new(:description, :days) do
  # Returns the first character of the interval's description.
  # @return [String] The first character of the description.
  def code
    description[0]
  end

  # Determines if a task is due based on the given date.
  # @param date [Date] The date to compare against.
  # @return [Boolean] True if the interval has elapsed since the given date.
  def due?(date)
    (Date.today - date).to_i >= days
  end
end

# Predefined intervals for task scheduling.

# @return [Interval] Represents a one-time task.
ONCE = Interval.new('Once', 0)

# @return [Interval] Represents a weekly task.
WEEKLY = Interval.new('Weekly', 7)

# @return [Interval] Represents a monthly task.
MONTHLY = Interval.new('Monthly', 30)

# @return [Interval] Represents a bi-monthly task (every 61 days).
BIMONTHLY = Interval.new('Bi-Monthly', 61)

# @return [Interval] Represents a quarterly task (every 91 days).
QUARTERLY = Interval.new('Quarterly', 91)

# @return [Interval] Represents a half-yearly task (every 182 days).
HALF_YEARLY = Interval.new('Halfyearly', 182)

# @return [Interval] Represents a yearly task (every 365 days).
YEARLY = Interval.new('Yearly', 365)

# A hash mapping interval codes to their corresponding interval objects.
# Each code is the first character of the interval's description.
# @return [Hash{String => Interval}]
INTERVALS = {
  ONCE.code => ONCE,
  WEEKLY.code => WEEKLY,
  MONTHLY.code => MONTHLY,
  BIMONTHLY.code => BIMONTHLY,
  QUARTERLY.code => QUARTERLY,
  HALF_YEARLY.code => HALF_YEARLY,
  YEARLY.code => YEARLY
}.freeze

# An array of all available interval codes.
# @return [Array<String>]
CODES = INTERVALS.keys

# A constant representing the code to clear an interval.
# @return [String]
CLEAR_INTERVAL = 'X'

# Represents a notification for a task based on a specific interval.
# @!attribute [r] task
#   @return [String] The name of the task to be notified about.
# @!attribute [r] interval
#   @return [String] The interval code for the task's recurrence.
# @!attribute [r] triggered
#   @return [Date] The date when the task was last triggered.
Notification = Struct.new(:task, :interval, :triggered) do
  # Converts the notification details into a human-readable string.
  # @return [String] A formatted string describing the notification.
  def to_s
    i = INTERVALS[interval]
    if i
      time_desc = if i == ONCE
                    'after date'
                  else
                    'last time triggered'
                  end
      "Task '#{task}' to be executed #{i.description}; #{time_desc} #{triggered}"
    else
      "Notification #{task}, invalid interval='#{interval}', triggered=#{triggered}"
    end
  end
end

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
    @config.entries.each do |cfg|
      next unless cfg.notifications&.count&.positive?

      puts cfg.description
      cfg.notifications.each do |n|
        puts "- #{n}"
      end
    end
  end
end
