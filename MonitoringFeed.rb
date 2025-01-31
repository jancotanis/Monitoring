# frozen_string_literal: true
require 'yaml'
require 'rss'
require 'open-uri'
require_relative 'utils'

# Represents a vulnerability detected in an RSS feed.
#
# This struct encapsulates information about a vulnerability, including its
# feed item details, associated companies, and its priority level.
#
# @attr_reader [RSS::Rss::Channel::Item] feed_item The RSS feed item containing vulnerability details.
# @attr_reader [Array<Company>] companies List of companies potentially affected by the vulnerability.
# @attr_reader [Boolean] high_priority? Indicates if the vulnerability is high priority.
Vulnerability = Struct.new(:feed_item, :companies, :high_priority?) do
  # Returns the title of the vulnerability.
  #
  # @return [String] The title of the RSS feed item.
  def title
    feed_item.title
  end

  # Provides a detailed description of the vulnerability.
  #
  # Includes the feed item's title, link, and a list of affected companies,
  # along with an advisory to act within 72 hours.
  #
  # @return [String] Detailed vulnerability description.
  def description
    companies_list = companies.map(&:description).join("\n- ")
    "#{feed_item.title}\n#{feed_item.link}\n\n" \
    "*** Controleer de klanten met een SLA en onderneem aktie binnen 72 uur (3 werkdagen)\n" \
    "- #{companies_list}"
  end
end

# Base class for monitoring changes in an RSS feed.
#
# The `MonitoringFeed` class provides functionality to monitor an RSS feed for new items,
# cache alerts locally, and filter vulnerabilities based on their publication date and priority.
class MonitoringFeed
  attr_reader :source

  # Initializes a new `MonitoringFeed` instance.
  #
  # Sets up the RSS feed monitoring with cache management and company filtering.
  #
  # @param config [Hash] Configuration options, including company monitoring preferences.
  # @param feed [String] URL of the RSS feed to monitor.
  # @param source [String] The source identifier for this feed (e.g., "DTC" or "NCSC").
  def initialize(config, feed, source)
    @config = config
    @feed = feed
    @feedcache = source.downcase
    @source = source
    @last_time = Time.new(0)

    # Backwards compatibility: rename old cache files
    old_cache_name = "./monitor#{@feedcache}alerts.yml"
    File.rename(old_cache_name, cache_name) if File.file?(old_cache_name)

    # Load cache if it exists, or initialize it
    if File.file?(cache_name)
      @last_time = File.mtime(cache_name)
      @alerts = YAML.load_file(cache_name)
    else
      @alerts = []
    end

    # Filter companies to monitor based on config
    @companies = @config.entries.select(&:monitor_dtc)
  end

  # Fetches a list of vulnerabilities from the RSS feed.
  #
  # Filters the feed to only include new items published since the last run.
  #
  # @param since [Time, nil] Only fetch items published after this time. Defaults to the last cached time.
  # @return [Array<Vulnerability>] List of vulnerabilities detected since the specified time.
  def get_vulnerabilities_list(since = nil)
    items = {}
    since ||= @last_time

    # Fetch and parse the RSS feed
    URI.open(@feed) do |rss|
      feed = RSS::Parser.parse(rss, false)

      # Deduplicate items by link, sorting by publication date
      feed.items.sort_by(&:pubDate).each do |item|
        items[item.link] ||= item
      end
    end

    # Identify new vulnerabilities
    vulnerabilities = []
    items.each_value do |item|
      if report_item?(item)
        guid = item.link
        unless @alerts.include?(guid)
          @alerts << guid
          vulnerabilities << Vulnerability.new(item, @companies, high_priority?(item)) if item.pubDate > since
        end
      end
    end

    update_cache
    vulnerabilities
  end

  # Determines if a feed item is high priority.
  #
  # This method is meant to be overridden in subclasses to provide specific
  # criteria for determining high priority vulnerabilities.
  #
  # @param item [RSS::Rss::Channel::Item] The RSS item to evaluate.
  # @return [Boolean] `true` if the item is high priority, `false` otherwise.
  def high_priority?(_item)
    false
  end

  # Determines if a feed item needs to be reported or ignored
  #
  # This method is meant to be overridden in subclasses to provide specific
  # criteria for determining suppression of items.
  #
  # @param item [RSS::Rss::Channel::Item] The RSS item to evaluate.
  # @return [Boolean] `true` the item will be reported.
  def report_item?(_item)
    true
  end

  def update_cache
    # Update the cache
    FileUtil.write_file(cache_name(), YAML.dump(@alerts))
  end

  private

  # Returns the name of the cache file.
  #
  # @return [String] The path to the cache file.
  def cache_name
    "./monitor-#{@feedcache}-alerts.yml"
  end
end
