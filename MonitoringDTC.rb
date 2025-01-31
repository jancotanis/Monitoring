# frozen_string_literal: true

require 'yaml'
require 'rss'
require 'open-uri'
require_relative 'utils'
require_relative 'MonitoringFeed'

# A specialized monitoring class for fetching and analyzing DTC advisories via RSS.
#
# The `MonitoringDTC` class extends `MonitoringFeed` to monitor advisories
# from the Dutch Digital Trust Center (DTC). It evaluates advisories to determine
# if they are high priority based on specific keywords in their titles.
#
# @see MonitoringFeed
class MonitoringDTC < MonitoringFeed
  # Initializes a new `MonitoringDTC` instance.
  #
  # This sets up the monitoring feed for DTC advisories using the provided configuration.
  #
  # @param config [Hash] Configuration options passed to the parent class.
  #
  # @example
  #   config = { alert_threshold: 'high', log_level: 'info' }
  #   feed = MonitoringDTC.new(config)
  def initialize(config)
    super(config, 'https://www.digitaltrustcenter.nl/rss-cyberalerts.xml', 'DTC')
  end

  # Determines if an advisory is high priority based on its title.
  #
  # An advisory is considered high priority if its title contains the terms
  # "KRITIEK" (Critical) or "ERNSTIG" (Severe), "ACTIEF MISBRUIK"  which are case-insensitive.
  #
  # @param item [RSS::Rss::Channel::Item] The RSS item to evaluate.
  # @return [Boolean] `true` if the advisory is high priority, `false` otherwise.
  #
  # @example
  #   item.title = "Kritieke kwetsbaarheid ontdekt in software"
  #   feed.high_priority?(item) # => true
  #
  #   item.title = "Minder ernstige kwetsbaarheid in webapplicatie"
  #   feed.high_priority?(item) # => false
  def high_priority?(item)
    ['KRITIEK', 'ERNSTIG', 'ACTIEF MISBRUIK'].any? { |term| item.title.upcase.include? term }
  end
end
