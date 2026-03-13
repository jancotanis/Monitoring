# frozen_string_literal: true

require 'yaml'
require 'rss'
require 'open-uri'
require 'json'
require_relative 'utils'
require_relative 'MonitoringFeed'
require_relative 'persistent_cache'

# class CVEAlert retrieves CVE details from the MITRE CVE API
# and extracts the highest CVSS base score.
#
# Example usage:
#   cve = class CVEAlert.new("CVE-2024-12345")
#   puts cve.data  # Full JSON response
#   puts cve.score # Highest CVSS score
class CVEAlert
  attr_reader :data, :score

  # Initializes the class and loads CVE data.
  #
  # @param id [String] The CVE ID
  def initialize(id)
    @id = id.upcase
    @data = {}
    @score = -1
    fetch_data
  end

  # Returns the list of affected vendors from the CVE data.
  #
  # @return [Array<String>] List of vendor names
  def vendors
    return [] unless @data['containers']&.dig('cna', 'affected')

    @data['containers']['cna']['affected'].map { |a| a['vendor'] }.compact.uniq
  end

  # Returns the list of affected products from the CVE data.
  #
  # @return [Array<Hash>] List of product info hashes with :vendor, :product, :cpes keys
  def products
    return [] unless @data['containers']&.dig('cna', 'affected')

    @data['containers']['cna']['affected'].map do |affected|
      {
        vendor: affected['vendor'],
        product: affected['product'],
        cpes: affected['cpes'] || []
      }
    end
  end

  # Returns a hash with vendor names as keys and arrays of affected products as values.
  #
  # @return [Hash{String => Array<String>}] Hash mapping vendor name to list of product names
  def vendor_products
    return {} unless @data['containers']&.dig('cna', 'affected')

    result = {}
    @data['containers']['cna']['affected'].each do |affected|
      vendor = affected['vendor']
      product = affected['product']
      next if vendor.nil? || product.nil?

      result[vendor] ||= []
      result[vendor] << product unless result[vendor].include?(product)
    end
    result
  end

  # Returns the CVE description.
  #
  # @return [String] CVE description or empty string
  def description
    return '' unless @data['containers']&.dig('cna', 'descriptions')

    desc = @data['containers']['cna']['descriptions'].find { |d| d['lang'] == 'en' }
    desc ? desc['value'] : ''
  end

  private

  # Fetches and processes the CVE data from the MITRE API.
  def fetch_data
    url = json_url
    @data = parse_json(CVEAlert.request_data(url))
    @score = CVEAlert.extract_highest_cvss_score(@data)
  rescue OpenURI::HTTPError => e
    warn "Failed to fetch CVE data: #{e.message}" unless e.message['404']
    @score = nil
  end

  # Constructs the API URL for fetching CVE data.
  #
  # @return [String] The formatted API URL
  def json_url
    "https://cveawg.mitre.org/api/cve/#{@id}"
  end

  # Makes an HTTP request to fetch CVE data.
  #
  # @param url [String] The API URL
  # @return [String] The raw JSON response
  def self.request_data(url)
    URI.parse(url).open('User-Agent' => "Ruby/#{RUBY_VERSION}",
                        'From' => 'info@monitoring.ncsc',
                        'Referer' => url).read
  end

  # Parses JSON data safely.
  #
  # @param json_str [String] The raw JSON string
  # @return [Hash] The parsed JSON data
  def parse_json(json_str)
    JSON.parse(json_str)
  rescue JSON::ParserError => ex
    warn "JSON parsing error: #{ex.message}"
    {}
  end

  # Extracts the highest CVSS base score from the CVE data.
  #
  # @param data [Hash] The parsed CVE data
  # @return [Float] The highest CVSS score found, or -1 if unavailable
  def self.extract_highest_cvss_score(data)
    return -1 unless data

    data.dig('containers', 'cna', 'metrics')&.flat_map do |metric|
      metric.values
            .select { |val| val.is_a?(Hash) && val.key?('baseScore') }
            .map { |val| val['baseScore'] }
    end&.compact&.max || -1
  end
end

# NCSCTextAdvisory fetches and processes text-based security advisories
# from the Dutch National Cyber Security Centre (NCSC).
#
# Example usage:
#   advisory = NCSCTextAdvisory.new("2024-001")
#   puts advisory.advisory  # Full advisory text
#   puts advisory.cve       # Extracted CVE IDs
class NCSCTextAdvisory
  attr_reader :id, :advisory, :cve, :title

  # Initializes the class and loads the advisory.
  #
  # @param id [String] The advisory ID
  def initialize(id)
    @id = id.upcase
    @advisory = ''
    @cve = []
    @title = ''
    load_text_advisory
  end

  # Returns unique vendor/products from all CVEs in this advisory.
  #
  # @return [Hash{String => Array<String>}] Hash mapping vendor name to list of product names
  def vendor_products
    result = {}
    @cve.each do |cve_id|
      cve = CVEAlert.new(cve_id)
      cve.vendor_products.each do |vendor, products|
        result[vendor] ||= []
        products.each do |product|
          result[vendor] << product unless result[vendor].include?(product)
        end
      end
    end
    result
  end

  private

  # Fetches and processes the advisory text from the NCSC website.
  def load_text_advisory
    url = text_url
    data = fetch_data(url)
    @advisory = NCSCTextAdvisory.strip_pgp(data)
    @cve = NCSCTextAdvisory.parse_cve_ids(@advisory)
    @title = NCSCTextAdvisory.parse_title(@advisory)
  end

  # Extracts the title from the advisory text.
  #
  # @param text [String] The advisory text
  # @return [String] The extracted title or empty string
  def self.parse_title(text)
    return '' unless text

    match = text.match(/Titel\s*:\s*(.+?)(?:\n|$)/m)
    match ? match[1].strip : ''
  end

  # Fetches data from the given URL.
  #
  # @param url [String] The advisory URL
  # @return [String] The raw advisory text
  def fetch_data(url)
    URI.parse(url).open('User-Agent' => "Ruby/#{RUBY_VERSION}",
                        'From' => 'info@monitoring.ncsc',
                        'Referer' => url).read
  rescue OpenURI::HTTPError => e
    warn "Failed to fetch advisory: #{e.message}"
    ''
  end

  # Extracts CVE IDs from the advisory text.
  #
  # @param text [String] The advisory text
  # @return [Array<String>] List of CVE IDs
  def self.parse_cve_ids(text)
    return [] unless text

    text.scan(/CVE-\d{4}-\d{4,5}/).uniq
  end

  # Removes PGP signature wrappers from the advisory text.
  #
  # @param text [String] The raw advisory text
  # @return [String] The cleaned advisory content
  def self.strip_pgp(text)
    return '' unless text

    match = text.match(/-----BEGIN PGP SIGNED MESSAGE-----(.*?)-----BEGIN PGP SIGNATURE-----/m)
    match ? match[1].strip : text
  end

  # Constructs the advisory text URL.
  # Original url  not supported and is client side redirected
  #   "https://advisories.ncsc.nl/advisory?id=#{@id}&format=plain"
  #
  # @return [String] The formatted advisory URL
  def text_url
    year = @id.split('-')[1]
    "https://advisories.ncsc.nl/#{year}/#{@id.downcase}.txt"
  end
end

# A specialized monitoring class for fetching and analyzing NCSC advisories via RSS.
#
# The `MonitoringNCSC` class extends the functionality of `MonitoringFeed` to monitor
# advisories from the Dutch National Cyber Security Centre (NCSC). It provides a mechanism
# to prioritize advisories based on probability and impact levels.
#
# @see MonitoringFeed
class MonitoringNCSC < MonitoringFeed
  CUTOFF_SCORE = 9

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
    @cve_cache = PersistentCache.new('./cve-scores.yml')
    @ncsc_cache = PersistentCache.new('./ncsv-scores.yml')
    super(config, 'https://advisories.ncsc.nl/rss/advisories', 'NCSC')
  end

  # Update caches
  def update_cache
    @cve_cache.persist_cache
    @ncsc_cache.persist_cache
    super
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
    if (match = item.title.match(%r{\[([HML])/([HM])\]}))
      probability = match[1]
      impact = match[2]
    end

    probability == 'H' || impact == 'H'
  end

  # Determines if an item is to be reported based on its associated CVE scores.
  #
  # @param item [Object] The item containing a link with an NCSC advisory ID.
  # @return [Boolean] True if the highest CVSS score is 9 or above (which is CRITICAL), otherwise false.
  def report_item?(item)
    # Extract NCSC advisory ID from the item's link
    id = item.link[/id=(NCSC-\d{4}-\d{4})/, 1]

    # get cached score
    # start with -1 so we have a number
    scores = [-1]
    score = @ncsc_cache.fetch(id) do
      # Fetch the NCSC advisory details
      ncsc = NCSCTextAdvisory.new(id)

      ncsc.cve.each do |cve_id|
        scores << @cve_cache.fetch(cve_id) do
          CVEAlert.new(cve_id).score
        end
      end

      score = scores.compact.max

      # cache score unless we had an unknown score
      if (score >= CUTOFF_SCORE) || !scores.include?(nil)
        # return score from loop
        score
      end
    end

    # Return true if the highest score is CUTOFF_SCORE or above
    [-1, score].compact.max >= CUTOFF_SCORE
  end
end
