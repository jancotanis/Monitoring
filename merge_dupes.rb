# frozen_string_literal: true

# Standalone script to find and merge duplicate customer entries in monitoring.cfg.
#
# Duplicate entries are identified by fingerprint matching (ignoring punctuation,
# spacing, and legal entity suffixes). The script shows a preview of what would
# be merged and asks for confirmation before saving.
#
# Usage:
#   ruby merge_dupes.rb

require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

cfg = MonitoringConfig.new
duplicates = cfg.find_duplicates

if duplicates.empty?
  puts 'No duplicate entries found.'
  exit(0)
end

puts "Found #{duplicates.size} duplicate group(s):\n\n"

duplicates.each do |entries|
  canonical = entries.max_by { |e| [e.source.size, e.description.length] }
  duplicates_in_group = entries - [canonical]

  puts "  KEEP  #{canonical.description}"
  puts "         sources: #{canonical.source.join(', ')}"
  puts "         ticket: #{canonical.create_ticket}, endpoints: #{canonical.monitor_endpoints}, backup: #{canonical.monitor_backup}"

  duplicates_in_group.each do |dup|
    puts "  MERGE #{dup.description}"
    puts "         sources: #{dup.source.join(', ')}"
    puts "         ticket: #{dup.create_ticket}, endpoints: #{dup.monitor_endpoints}, backup: #{dup.monitor_backup}"
  end
  puts
end

print "Merge #{duplicates.size} duplicate group(s)? [y/N] "
answer = gets&.chomp
unless answer&.downcase.eql?('y')
  puts 'Aborted.'
  exit(0)
end

duplicates.each { |group| cfg.merge_group(group) }
cfg.save_config

puts "Merged #{duplicates.size} group(s). Config saved."
