# frozen_string_literal: true

require 'date'

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

# @return [Interval] Represents a yearly task (every 365 days).
TWO_YEARLY = Interval.new('Twoyearly', 730)

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
  YEARLY.code => YEARLY,
  TWO_YEARLY.code => TWO_YEARLY
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
      time_desc = (i == ONCE) ? 'after date' : 'last time triggered'
      "Task '#{task}' to be executed #{i.description}; #{time_desc} #{triggered}"
    else
      "Notification #{task}, invalid interval='#{interval}', triggered=#{triggered}"
    end
  end
end
