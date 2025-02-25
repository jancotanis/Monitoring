# frozen_string_literal: true

# Matcher is responsible for matching companies between Hudu and a monitoring configuration.
#
# This class attempts to find exact or partial matches between companies in the Hudu system
# and their corresponding monitoring configurations.
#
# @example Usage
#   matcher = Matcher.new(hudu_companies, monitoring_config)
#   puts matcher.matches
#   puts matcher.nonmatches
#
class Matcher
  attr_reader :matches, :nonmatches

  # Initializes the Matcher with Hudu companies and monitoring configuration.
  #
  # It automatically attempts to match companies upon initialization.
  #
  # @param hudu_companies [Array<Object>] A list of companies from Hudu.
  # @param monitoring_config [Object] The monitoring configuration containing company entries.
  def initialize(hudu_companies, monitoring_config)
    @hudu = hudu_companies
    @portal = monitoring_config
    @matches, @nonmatches = match(@hudu, @portal)
  end

  private

  # Matches Hudu companies with monitoring configuration entries.
  #
  # This method first attempts an exact match by description. If an exact match is not found,
  # it performs a partial match unless the company is named "test". If multiple matches are found,
  # it selects the first and logs a warning about duplicates.
  #
  # @param hudu [Array<Object>] A list of companies from Hudu.
  # @param monitoring [Object] The monitoring configuration containing company entries.
  #
  # @return [Array<Hash, Array>] A tuple containing matched companies as a hash
  #   (`{ company => monitoring_entry }`) and a list of non-matching companies.
  def match(hudu, monitoring)
    matches = {}
    nonmatches = []
    hudu.each do |company|
      mon = monitoring.by_description(company.name)
      name = company.name.downcase

      # No exact match found and skip 'test' company
      if mon.nil? && !'test'.eql?(name)
        if mon = partial_match(monitoring.entries, name)&.first
          puts " Partial match found: #{company.name} / #{mon.description}" if mon
          puts "* Duplicate match for #{mon.description}" if mon.touched?
          mon.touch
        end
      end

      if mon
        matches[company] = mon
      else
        nonmatches << company
      end
    end
    [matches, nonmatches]
  end

  # Checks if a given company name partially matches any company descriptions and returns the matches.
  #
  # This method performs a case-insensitive check to see if the `company_name` is a substring
  # of any company's description or vice versa.
  #
  # @param companies [Array] An array of objects that must respond to `description`.
  # @param company_name [String] The company name to check for partial matches.
  # @return [Array] of matching company names/descriptions
  #
  # @example
  #   companies = [OpenStruct.new(description: "TechCorp"), OpenStruct.new(description: "InnoSoft")]
  #   partial_match?(companies, "tech")           #=> ['TechCorp']
  #   partial_match?(companies, "innosoftware")   #=> ['InnoSoft']
  #   partial_match?(companies, "apple")          #=> []
  #
  def partial_match(companies, company_name)
    companies.select do |company|
      name = company.description.downcase
      company_name.include?(name) || name.include?(company_name)
    end
  end
end
