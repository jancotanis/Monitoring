# frozen_string_literal: true

require 'yaml'
require 'rss'
require 'open-uri'
require 'json'
require_relative 'utils'
require_relative 'MonitoringFeed'

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

  private

  # Fetches and processes the CVE data from the MITRE API.
  def fetch_data
    url = json_url
puts url
    @data = parse_json(request_data(url))
    @score = extract_highest_cvss_score(@data)
  rescue OpenURI::HTTPError => e
    warn "Failed to fetch CVE data: #{e.message}"
    # assume 404, this means CVE id has been reserved and information about the vulnerability is not publicly disclosed
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
  def request_data(url)
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
  rescue JSON::ParserError => e
    warn "JSON parsing error: #{e.message}"
    {}
  end

  # Extracts the highest CVSS base score from the CVE data.
  #
  # @param data [Hash] The parsed CVE data
  # @return [Float] The highest CVSS score found, or -1 if unavailable
  def extract_highest_cvss_score(data)
    return -1 unless data

    data.dig('containers', 'cna', 'metrics')&.flat_map do |metric|
      metric.values
            .select { |v| v.is_a?(Hash) && v.key?('baseScore') }
            .map { |v| v['baseScore'] }
    end&.compact&.max || -1
  end
end

# CVEScoreCache manages a local cache of CVE scores to minimize API calls.
#
# Example usage:
#   cache = CVECache.new
#   score = cache.cve_score("CVE-2024-12345")
#   cache.save
class CVEScoreCache
  SCORE_FILE = 'cve_scores.yml'

  def initialize
    @updated = false
    load_scores
  end

  # Retrieves the CVSS score for a given CVE ID, fetching from API if necessary.
  #
  # @param cve_id [String] The CVE identifier
  # @return [Float] The CVSS score
  def cve_score(cve_id)
    raise ArgumentError, 'No CVE ID given' if cve_id.nil? || cve_id.strip.empty?

    cve_id = cve_id.upcase
    @cve_scores[cve_id] ||= fetch_cve_score(cve_id)
  end

  # Saves the updated CVE scores to the YAML file.
  def save
    return unless @updated

    File.write(SCORE_FILE, @cve_scores.to_yaml)
    @updated = false
  end

  private

  # Loads cached CVE scores from a YAML file.
  def load_scores
    @updated = false
    @cve_scores = File.exist?(SCORE_FILE) ? YAML.load_file(SCORE_FILE) || {} : {}
  rescue StandardError => e
    warn "Error loading #{SCORE_FILE}: #{e.message}"
    @cve_scores = {}
  end

  # Fetches CVE score from API and updates cache.
  #
  # @param cve_id [String] The CVE identifier
  # @return [Float] The CVSS score
  def fetch_cve_score(cve_id)
    cve = CVEAlert.new(cve_id)
    score = cve.score
    @updated = true if score != -1
    score
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
  attr_reader :advisory, :cve

  # Initializes the class and loads the advisory.
  #
  # @param id [String] The advisory ID
  def initialize(id)
    @id = id.upcase
    @advisory = ''
    @cve = []
    load_text_advisory
  end

private

  # Fetches and processes the advisory text from the NCSC website.
  def load_text_advisory
    url = text_url
puts url
    data = fetch_data(url)
    @advisory = strip_pgp(data)
    @cve = parse_cve_ids(@advisory)
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
  def parse_cve_ids(text)
    return [] unless text

    text.scan(/CVE-\d{4}-\d{4,5}/).uniq
  end

  # Removes PGP signature wrappers from the advisory text.
  #
  # @param text [String] The raw advisory text
  # @return [String] The cleaned advisory content
  def strip_pgp(text)
    return '' if text.nil?

    match = text.match(/-----BEGIN PGP SIGNED MESSAGE-----(.*?)-----BEGIN PGP SIGNATURE-----/m)
    match ? match[1].strip : text
  end

  # Constructs the advisory text URL.
  #
  # @return [String] The formatted advisory URL
  def text_url
    "https://advisories.ncsc.nl/advisory?id=#{@id}&format=plain"
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
    @cache = CVEScoreCache.new
    super(config, 'https://advisories.ncsc.nl/rss/advisories', 'NCSC')
  end

  # Update caches
  def update_cache
    @cache.save
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
    if (match = item.title.match( %r(\[([HML])/([HM])\])))
      probability = match[1]
      impact = match[2]
    end

    (probability == 'H' || impact == 'H')
  end

  # Determines if an item is to be reported based on its associated CVE scores.
  #
  # @param item [Object] The item containing a link with an NCSC advisory ID.
  # @return [Boolean] True if the highest CVSS score is 9 or above (which is CRITICAL), otherwise false.
  def report_item?(item)
    # Extract NCSC advisory ID from the item's link
    id = item.link[/id=(NCSC-\d{4}-\d{4})/, 1]

    # Fetch the NCSC advisory details
    ncsc = NCSCTextAdvisory.new(id)

    score = -1
    ncsc.cve.each do |cve_id|
      cve_score = @cache.cve_score(cve_id)
      score = cve_score if cve_score && (cve_score > score)
    end

    # Return true if the highest score is 9 or above
    score >= 9
  end
end
