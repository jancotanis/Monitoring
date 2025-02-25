# frozen_string_literal: true

require 'yaml'
require_relative 'utils'

MONITORING_CFG = 'monitoring.cfg'

# Struct for managing configuration data, including monitoring and SLA details.
#
# This struct holds configuration data for a system, such as monitoring settings, SLA information,
# ticket creation, notifications, and alerts. It provides utility methods for interacting with
# monitoring status and tracking if the object has been "touched" (modified).
ConfigData = Struct.new(
  :id, :description, :source, :sla, :monitor_endpoints, :monitor_connectivity, :monitor_backup,
  :monitor_dtc, :create_ticket, :notifications, :backup_domain, :last_backup, :reported_alerts, :endpoints
) do
  def initialize(*)
    super
    @touched = false

    # Set default values for the fields if they are not provided
    self.source               ||= []
    self.sla                  ||= []
    self.monitor_endpoints    ||= false
    self.monitor_connectivity ||= false
    self.monitor_backup       ||= false
    self.monitor_dtc          ||= false
    self.create_ticket        ||= false
    self.reported_alerts      ||= []
    self.notifications        ||= []
  end

  # Checks if any monitoring options are enabled.
  #
  # This method returns `true` if at least one of the monitoring options (endpoints, connectivity,
  # backup, or DTC) is enabled, and `false` otherwise.
  #
  # @return [Boolean] `true` if any monitoring setting is enabled, `false` otherwise.
  def monitoring?
    monitor_endpoints || monitor_connectivity || monitor_backup || monitor_dtc
  end

  # Marks this object as "touched" (modified).
  #
  # This method sets the `@touched` flag to `true`, indicating that the object has been modified.
  #
  # @return [void]
  def touch
    @touched = true
    self
  end

  # Marks this object as "untouched".
  #
  # This method sets the `@touched` flag to `false`, indicating that the object has not been modified.
  #
  # @return [void]
  def untouch
    @touched = false
    self
  end

  # Checks if this object has been marked as "touched".
  #
  # This method returns the value of the `@touched` flag.
  #
  # @return [Boolean] `true` if the object has been modified, `false` otherwise.
  def touched?
    @touched
  end
end

# Class for managing and manipulating monitoring configuration data.
#
# This class handles operations on a configuration loaded from a YAML file. It allows for searching,
# modifying, deleting, and saving configuration entries. It also supports adding new tenant entries
# and removing unused configuration data.
#
# @see ConfigData
class MonitoringConfig
  attr_reader :config
  alias entries config

  # Initializes the MonitoringConfig instance by loading the configuration from a YAML file
  # or initializing an empty configuration array if the file does not exist.
  #
  # @return [void]
  def initialize
    if File.file?(MONITORING_CFG)
      @config = YAML.load_file(MONITORING_CFG)
      @config.each(&:untouch)
    else
      @config = []
    end
  end

  # Returns the first matching configuration entry by its ID.
  #
  # Searches the configuration for an entry with the specified ID.
  #
  # @param idx [String] The ID to search for.
  #
  # @return [ConfigData, nil] The matching configuration entry, or nil if not found.
  def by_id(idx)
    result = @config.select { |cfg| cfg.id.eql?(idx) }
    MonitoringConfig.first_result(result)
  end

  # Returns the first matching configuration entry by its description.
  #
  # Searches the configuration for an entry with the specified description.
  #
  # @param desc [String] The description to search for.
  #
  # @return [ConfigData, nil] The matching configuration entry, or nil if not found
  def by_description(desc)
    result = @config.select { |cfg| cfg.description.upcase.eql?(desc.upcase) }
    MonitoringConfig.first_result(result)
  end

  # Deletes a configuration entry from the list.
  #
  # @param entry [ConfigData] The configuration entry to delete.
  #
  # @return [void]
  def delete_entry(entry)
    @config.delete(entry)
  end

  # Removes all unused (untouched) configuration entries from the list.
  #
  # Unused entries are those that have not been marked as "touched." Each removed entry is logged.
  #
  # @return [void]
  def compact!
    # remove all unused entries
    @config.reject(&:touched?).each do |removed|
      puts " * removed customer #{removed.description}"
    end
    @config.select!(&:touched?)
  end

  # Saves the current configuration to a YAML file, sorted by description.
  #
  # The configuration is serialized into YAML format and saved to `MONITORING_CFG`.
  #
  # @return [void]
  def save_config
    FileUtil.write_file(MONITORING_CFG, YAML.dump(@config.sort_by { |tenant| tenant.description.upcase }))
  end

  # Loads new tenant configuration entries and adds them to the existing configuration.
  #
  # For each tenant, if the configuration entry is missing, it is created and added to the list.
  # Existing entries are updated with new source information if needed.
  #
  # @param source [String] The source associated with the tenants.
  # @param tenants [Array] The array of tenant objects to load into the configuration.
  #
  # @return [Array] The updated configuration list.
  def load_config(source, tenants)
    # add missing tenants config entries
    tenants.each do |tenant|
      id = tenant.id
      description = tenant.description

      cfg = by_description(description) || ConfigData.new(id, description, [source])
      # not found by description
      if cfg
        # check if we have a record with same id
        if found = by_id(id)
          # overwrite original item
          cfg = found
          puts "Rename tenant [#{cfg.description}] to [#{description}]"
        else
          # not renamed, add it
          puts "Nieuwe tenant [#{description}]"
          @config << cfg
        end
      end
      cfg.description = description
      cfg.source << source unless cfg.source.include? source
    end
    # update config
    @config
  end

  # Generates a configuration report for all companies and writes it to a markdown file.
  #
  # The method writes a report in markdown format to the `configuration.md` file. The report
  # includes columns for company description, notification counts, ticket creation, and monitoring
  # service statuses for several services (CloudAlly, Skykick, Sophos, Veeam, Integra365, Zabbix).
  #
  # The data for each company is collected from the `@config` instance variable and each company's
  # configuration is processed to generate the appropriate values for each column.
  #
  # @return [void] This method writes directly to a file and does not return any values.
  def report
    keys = %w[CloudAlly Skykick Sophos Veeam Integra365 Zabbix]
    report_file = 'configuration.md'

    # Open the report file and write the headers and company details.
    File.open(report_file, 'w') do |report|
      report.puts "| Company | Notifications | Ticket | Endpoints | Backup | Monitoring | DTC | #{keys.join(' | ')} |"
      report.puts "|:--|:--:|:--:|:--:|:--:|:--:|:--:|#{':--: | ' * keys.count}"

      @config.each do |cfg|
        puts cfg.description
        services = keys.map { |key| "#{sla_documentation(cfg, key)}|" }.join
        notifications = cfg.notifications.count if cfg.notifications&.count&.positive?

        # Write the data for the current company into the report
        report.puts "|#{cfg.description}|#{notifications}" \
                    "|#{MonitoringConfig.on_off(cfg.create_ticket)}|#{MonitoringConfig.on_off(cfg.monitor_endpoints)}" \
                    "|#{MonitoringConfig.on_off(cfg.monitor_backup)}|#{MonitoringConfig.on_off(cfg.monitor_connectivity)}" \
                    "|#{MonitoringConfig.on_off(cfg.monitor_dtc)}|#{services}"
      end
      puts "- #{report_file} written"
    end
  end

  private

  # Retrieves the SLA documentation for a given service key in the configuration.
  #
  # This method checks if the service `key` is included in the configuration's source. If it is,
  # it searches for the associated SLA. If found, it returns the SLA documentation with the service
  # key prefix removed. If no SLA is found, it returns an empty string.
  #
  # @param cfg [Object] The configuration object containing the service details.
  # @param key [String] The service key (e.g., "CloudAlly", "Skykick", etc.) to search for in the SLA.
  #
  # @return [String] The SLA documentation or an empty string if no SLA is found.
  def sla_documentation(cfg, key)
    return '' unless cfg.source.include?(key)

    sla = cfg.sla.grep(/#{key}/).first
    return 'x' if !sla || sla.empty?

    sla.gsub("#{key}-", '')
  end

  # Returns the first result and marks it as "touched".
  #
  # This method retrieves the first element from the provided result collection and invokes
  # the `touch` method on it (if the element exists). The first element is then returned.
  #
  # @param result [Array] The collection of results from which the first element is fetched.
  #
  # @return [Object, nil] The first element of the result collection, or `nil` if the collection is empty.
  def self.first_result(result)
    result.first&.touch
  end

  # Converts a boolean value to a human-readable "on" or "" (empty string).
  #
  # This method takes a boolean value and returns "on" if the value is true, or an empty string
  # if the value is false. It is useful for representing boolean values in a user-friendly format.
  #
  # @param bool [Boolean] The boolean value to convert.
  #
  # @return [String] "on" if the boolean is true, or an empty string if the boolean is false.
  def self.on_off(bool)
    bool ? 'on' : ''
  end
end
