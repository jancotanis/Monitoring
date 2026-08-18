# frozen_string_literal: true

require 'json'
require 'optparse'
require 'dotenv/load'

require_relative 'ninjaone_api'
require_relative 'MonitoringNCSC'
require_relative 'software_index'
require_relative 'utils'

module MonitoringSoftware
  class CLI
    def self.run(args)
      options = parse_options(args)
      indexer = SoftwareIndexer.new

      if options[:update]
        indexer.update_from_api
        puts 'Index updated successfully.'
        return
      end

      validate_search_options(options)

      if options[:cve]
        perform_cve_lookup(indexer, options)
      elsif options[:ncsc]
        perform_ncsc_lookup(indexer, options)
      else
        perform_search(indexer, options)
      end
    end

    def self.get_org_name(client, org_id)
      tenant = client.tenant_by_id(org_id)
      tenant&.name || org_id.to_s
    end

    def self.parse_options(args)
      options = { publisher: nil, product: nil, update: false, cve: nil, ncsc: nil }

      opt_parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ruby monitoring_software.rb [options]'

        opts.on('--update', 'Fetch software from API and build index') do
          options[:update] = true
        end

        opts.on('--publisher PUBLISHER', 'Search by publisher (partial match)') do |pub|
          options[:publisher] = pub
        end

        opts.on('--product PRODUCT', 'Search by product name (partial match)') do |prod|
          options[:product] = prod
        end

        opts.on('--cve CVE', 'Lookup CVE and find affected organizations') do |cve|
          options[:cve] = cve
        end

        opts.on('--ncsc ID', String, 'Check NCSC advisories for affected organizations') do |num|
          options[:ncsc] = num
        end

        opts.on('-?', '--help', 'Show this help') do
          puts opts
          puts
          puts 'Examples:'
          puts '  ruby monitoring_software.rb --update'
          puts '  ruby monitoring_software.rb --publisher "microsoft"'
          puts '  ruby monitoring_software.rb --product "sql"'
          puts '  ruby monitoring_software.rb --publisher "micro" --product "edge"'
          puts '  ruby monitoring_software.rb --cve "CVE-2025-1234"'
          puts '  ruby monitoring_software.rb --ncsc 10'
          exit
        end
      end

      opt_parser.parse!(args)
      options
    end

    def self.validate_search_options(options)
      if options[:cve]
        validate_cve_options(options)
        return
      end

      return if options[:ncsc] || options[:cve] || options[:publisher] || options[:product] || options[:update]

      puts 'Error: Specify --publisher and/or --product to search, --cve to lookup CVE, --ncsc to check NCSC advisories, or --update to build index.'
      puts 'Use --help for usage information.'
      exit 1
    end

    def self.validate_cve_options(options)
      return if options[:cve] =~ /^CVE-\d{4}-\d{4,5}$/i

      puts "Error: Invalid CVE format: #{options[:cve]}"
      puts 'CVE format should be like: CVE-2025-1234'
      exit 1
    end

    def self.perform_search(indexer, options)
      results = indexer.search(publisher: options[:publisher], product: options[:product])

      if results.empty?
        puts 'No matching software found.'
        exit
      end

      puts "Found #{results.count} matching software entries:"
      puts

      results.each do |r|
        device_ids = r['devices'] || []
        devices = device_ids.map { |id| indexer.devices_for(publisher: r['publisher'], product: r['name']).find { |d| d['id'] == id } }.compact
        orgs = r['organizations'] || []
        puts "Publisher: #{r['publisher']}"
        puts "Product:   #{r['name']}"
        hostnames = devices.map { |d| d['hostname'] || d['id'] }
        puts "Devices:   #{devices.count} (#{hostnames.first(5).join(', ')}#{', ...' if devices.count > 5})"
        puts "Orgs:     #{orgs.count} (#{orgs.first(5).join(', ')}#{', ...' if orgs.count > 5})"
        puts '-' * 40
      end
    end

    def self.perform_cve_lookup(indexer, options)
      cve_id = options[:cve].upcase

      puts "Looking up #{cve_id}..."

      cve = CVEAlert.get(cve_id)

      if cve.score.nil?
        puts "Error: CVE #{cve_id} not found or has no public details."
        exit 1
      end

      puts "CVE: #{cve_id} (CVSS: #{cve.score})"
      puts "Description: #{cve.description[0..200]}#{'...' if cve.description.length > 200}"
      puts

      client = indexer.client

      affected_products = cve.products

      if affected_products.empty?
        puts 'No affected products found in CVE data.'
        exit
      end

      puts 'Affected products:'
      cve.vendors.sort.each do |vendor|
        puts "- #{vendor}: #{cve.vendor_products[vendor].sort.join(', ')}"
      end

      puts "Affected vendors: #{cve.vendors.join(', ')}"
      puts "Affected products: #{affected_products.map { |p| p[:product] }.join(', ')}"
      puts

      org_results = {}
      total_devices = 0

      indexer.load_index

      affected_products.each do |affected|
        vendor = affected[:vendor]
        results = indexer.search(publisher: vendor)
        next if results.empty?

        results.each do |r|
          devices = indexer.devices_for(publisher: r['publisher'], product: r['name'])

          devices.each do |device|
            org_id = device['organization_id']
            next unless org_id

            org_results[org_id] ||= { products: {} }
            prod_name = r['name']

            org_results[org_id][:products][prod_name] ||= []
            unless org_results[org_id][:products][prod_name].any? { |d| d['id'] == device['id'] }
              org_results[org_id][:products][prod_name] << device
              total_devices += 1
            end
          end
        end
      end

      if org_results.empty?
        puts 'No matching software found in the software index.'
        exit
      end

      puts "Found #{org_results.keys.count} organization(s) with #{total_devices} affected device(s):"
      puts

      org_results.each do |org_id, data|
        org_name = get_org_name(client, org_id)
        puts "Organization: #{org_name} (id:#{org_id})"
        data[:products].each do |prod_name, devices|
          puts "  - #{prod_name} (#{devices.count} devices)"
          devices.first(10).each do |device|
            puts "      #{device['hostname'] || device['id']}"
          end
          puts '      ...' if devices.count > 10
        end
        puts
      end
    end

    def self.perform_ncsc_lookup(indexer, options)
      id = options[:ncsc]
      advisory = NCSCTextAdvisory.new(id)
      ncsc_vendor_products = advisory.vendor_products

      puts "NCSC Advisory: #{id}"
      puts "Title: #{advisory.title}"
      puts "CVEs found: #{advisory.cve.count}"
      puts

      if ncsc_vendor_products.empty?
        puts 'No affected vendors found in the advisory.'
        exit
      end

      client = indexer.client

      indexer.load_index

      vendor_results = {}

      ncsc_vendor_products.each do |vendor, ncsc_products|
        index_results = indexer.search(publisher: vendor)
        next if index_results.empty?

        vendor_results[vendor] ||= { index_products: [], ncsc_products: ncsc_products, product_orgs: {} }

        index_results.each do |r|
          prod_name = r['name']
          vendor_results[vendor][:index_products] << prod_name unless vendor_results[vendor][:index_products].include?(prod_name)

          matched = ncsc_products.any? { |np| prod_name.downcase.include?(np.downcase) || np.downcase.include?(prod_name.downcase) }

          vendor_results[vendor][:product_orgs][prod_name] ||= { devices: [], matched: matched, orgs: [] }

          devices = indexer.devices_for(publisher: r['publisher'], product: prod_name)

          devices.each do |device|
            org_id = device['organization_id']
            next unless org_id

            unless vendor_results[vendor][:product_orgs][prod_name][:orgs].include?(org_id)
              vendor_results[vendor][:product_orgs][prod_name][:orgs] << org_id
            end

            unless vendor_results[vendor][:product_orgs][prod_name][:devices].any? { |d| d['id'] == device['id'] }
              vendor_results[vendor][:product_orgs][prod_name][:devices] << device
            end
          end
        end
      end

      if vendor_results.empty?
        puts 'No matching software found in the software index for any vendor.'
        exit
      end

      puts 'Affected products:'
      ncsc_vendor_products.keys.sort.each do |vendor|
        puts "- #{vendor}: #{ncsc_vendor_products[vendor].sort.join(', ')}"
      end
      puts

      total_orgs = vendor_results.values.flat_map { |v| v[:product_orgs].values.flat_map { |p| p[:orgs] } }.flatten.uniq.count
      total_devices = vendor_results.values.flat_map { |v| v[:product_orgs].values.map { |p| p[:devices].count } }.flatten.sum

      puts "Found #{total_orgs} organizations with #{total_devices} affected devices"
      puts

      vendor_results.each do |vendor, data|
        puts "Software found for vendor #{vendor}:"

        data[:product_orgs].each do |prod_name, prod_data|
          # group devices per organization
          devices_by_org = {}
          prod_data[:devices].each do |d|
            org_id = d['organization_id']
            next unless org_id

            devices_by_org[org_id] ||= []
            devices_by_org[org_id] << d unless devices_by_org[org_id].any? { |x| x['id'] == d['id'] }
          end

          device_count = prod_data[:devices].count
          matched = prod_data[:matched]
          exclamation = matched ? '!!!' : '*'
          puts "#{exclamation} #{prod_name} (#{device_count} devices):"
          devices_by_org.each do |org_id, devices|
            org_name = get_org_name(client, org_id)
            puts "    #{org_name} (#{devices.count})"
            devices.first(10).each do |device|
              puts "      - #{device['hostname'] || device['id']}"
            end
            puts '      ...' if devices.count > 10
          end
        end
        puts
      end
    end
  end
end

MonitoringSoftware::CLI.run(ARGV) if __FILE__ == $PROGRAM_NAME
