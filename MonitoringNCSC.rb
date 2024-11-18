# frozen_string_literal: true

require 'yaml'
require 'rss'
require 'open-uri'
require_relative 'utils'
require_relative 'MonitoringFeed'

# A specialized monitoring class for fetching and analyzing NCSC advisories via RSS.
#
# The `MonitoringNCSC` class extends the functionality of `MonitoringFeed` to monitor
# advisories from the Dutch National Cyber Security Centre (NCSC). It provides a mechanism
# to prioritize advisories based on probability and impact levels.
#
# @see MonitoringFeed
class MonitoringNCSC < MonitoringFeed
  # Initializes a new `MonitoringNCSC` instance.
  #
  # This sets up the monitoring feed for NCSC advisories, using the provided configuration.
  #
  # @param config [Hash] Configuration options passed to the parent class.
  #
  # @example
  #   config = { alert_threshold: 'high', log_level: 'info' }
  #   feed = MonitoringNCSC.new(config)
  def initialize(config)
    super(config, 'https://advisories.ncsc.nl/rss/advisories', 'NCSC')
  end

  # Determines if an advisory is high priority based on its title.
  #
  # NCSC advisories include probability and impact levels in the title,
  # formatted as `[Probability/Impact]`, where:
  # - `H` stands for High
  # - `M` stands for Medium
  # - `L` stands for Low
  #
  # An advisory is considered high priority if either the probability or
  # impact level is `H` (High).
  #
  # @param item [RSS::Rss::Channel::Item] The RSS item to evaluate.
  # @return [Boolean] `true` if the advisory has a high probability or impact, `false` otherwise.
  #
  # @example
  #   item.title = "NCSC-2024-0369 [1.01] [M/H] Vulnerabilities fixed in ..."
  #   feed.high_priority?(item) # => true
  #
  # @note Titles not containing probability/impact levels will default to `false`.
  def high_priority?(item)
    probability = impact = '?'

    # Extract probability and impact levels from the advisory title
    if (match = item.title.match( %r(\[([HML])\/([HM])\])))
      probability = match[1]
      impact = match[2]
    end

    (probability == 'H' || impact == 'H')
  end
end
