# frozen_string_literal: true

require 'json'
require 'optparse'
require 'dotenv/load'

require_relative 'ninjaone_api'
require_relative 'MonitoringNCSC'
require_relative 'utils'

module MonitoringSoftware

  CACHE_FILE = 'software-index.json'

  class SoftwareIndexer

    attr_reader :index

    def initialize
      @index = nil
    end

    def update_from_api
      puts 'Fetching software from NinjaOne API...'

      client = NinjaOne::ClientWrapper.new(
        ENV.fetch('NINJA1_HOST'),
        ENV.fetch('NINJA1_CLIENT_ID'),
        ENV.fetch('NINJA1_CLIENT_SECRET'),
        false
      )

      puts 'Fetching device organization mapping...'
      device_org_map = fetch_device_org_mapping(client)
      puts "Found #{device_org_map.keys.count} devices"
      raw = client.api.queries_software
      puts "Retrieved #{raw.count} software entries"
      @index = build_index(raw, device_org_map)
      save_index

      puts "Index saved to #{CACHE_FILE}"
      puts "Indexed #{@index.keys.count} publishers"

      @index
    end

    def fetch_device_org_mapping(client)
      devices = client.api.devices

      mapping = {}

      devices.each do |device|
        device_id = get_property(device, :id)
        org_id = get_property(device, :organizationId)
        mapping[device_id] = org_id unless device_id.nil?
      end

      mapping
    end

    def build_index(raw_software, device_org_map = {})
      indexed = {}

      raw_software.each do |sw|
        pub = normalize_string(get_property(sw, :publisher))
        name = normalize_string(get_property(sw, :name))
        device_id = get_property(sw, :deviceId)

        indexed[pub] ||= {}
        indexed[pub][name] ||= {
          'publisher' => get_property(sw, :publisher),
          'name' => get_property(sw, :name),
          'devices' => [],
          'organizations' => []
        }
        indexed[pub][name]['devices'] << device_id
      end

      indexed.each_value do |products|
        products.each_value do |data|
          data['devices'].uniq!
          data['devices'].sort!
          data['organizations'] = data['devices'].map { |d| device_org_map[d] }.compact.uniq.sort
        end
      end

      indexed
    end

    def get_property(obj, key)
      if obj.respond_to?(key)
        obj.send(key)
      elsif obj.is_a?(Hash)
        obj[key] || obj[key.to_s]
      end
    end

    def load_index
      return @index if @index

      unless File.exist?(CACHE_FILE)
        puts "Error: Index file #{CACHE_FILE} not found. Run with --update first."
        exit 1
      end

      @index = JSON.parse(File.read(CACHE_FILE))
    end

    def save_index
      File.write(CACHE_FILE, JSON.pretty_generate(@index))
    end

    def search(publisher: nil, product: nil)
      load_index

      results = []

      @index.each do |pub, products|
        next if pub.nil? || pub.strip.empty?

        pub_match = publisher.nil? || pub.downcase.include?(publisher.downcase)
        next unless pub_match

        products.each do |prod_name, data|
          next if prod_name.nil? || prod_name.strip.empty?
          next if data['publisher'].nil? || data['name'].nil?

          prod_match = product.nil? || prod_name.downcase.include?(product.downcase)
          results << data if prod_match
        end
      end

      results
    end

    def tenant_software(tenant_names, vendor_products, client = nil)
      load_index

      client ||= NinjaOne::ClientWrapper.new(
        ENV.fetch('NINJA1_HOST'),
        ENV.fetch('NINJA1_CLIENT_ID'),
        ENV.fetch('NINJA1_CLIENT_SECRET'),
        false
      )

      tenant_map = {}
      client.tenants.each do |tenant|
        tenant_map[tenant.name] = tenant.id
      end

      result = {}

      vendor_products.each do |vendor, _products|
        results = search(publisher: vendor)
        next if results.empty?

        results.each do |r|
          prod_name = r['name']
          org_ids = r['organizations'] || []

          org_ids.each do |org_id|
            tenant = client.tenant_by_id(org_id)
            next unless tenant && tenant_names.include?(tenant.name)

            result[tenant.name] ||= {}
            result[tenant.name][vendor] ||= []
            result[tenant.name][vendor] << prod_name unless result[tenant.name][vendor].include?(prod_name)
          end
        end
      end

      result
    end

    def normalize_string(str)
      str.nil? || str.strip.empty? ? 'Unknown' : str
    end
  end

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

        opts.on('-h', '--help', 'Show this help') do
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
        devices = r['devices'] || []
        orgs = r['organizations'] || []
        puts "Publisher: #{r['publisher']}"
        puts "Product:   #{r['name']}"
        puts "Devices:   #{devices.count} (#{devices.first(5).join(', ')}#{', ...' if devices.count > 5})"
        puts "Orgs:     #{orgs.count} (#{orgs.first(5).join(', ')}#{', ...' if orgs.count > 5})"
        puts '-' * 40
      end
    end

    def self.perform_cve_lookup(indexer, options)
      cve_id = options[:cve].upcase

      puts "Looking up #{cve_id}..."

      cve = CVEAlert.new(cve_id)

      if cve.score.nil?
        puts "Error: CVE #{cve_id} not found or has no public details."
        exit 1
      end

      puts "CVE: #{cve_id} (CVSS: #{cve.score})"
      puts "Description: #{cve.description[0..200]}#{'...' if cve.description.length > 200}"
      puts

      client = NinjaOne::ClientWrapper.new(
        ENV.fetch('NINJA1_HOST'),
        ENV.fetch('NINJA1_CLIENT_ID'),
        ENV.fetch('NINJA1_CLIENT_SECRET'),
        false
      )

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
        product = affected[:product]
        results = indexer.search(publisher: vendor)
        next if results.empty?

        results.each do |r|
          r['organizations'].each do |org_id|
            org_results[org_id] ||= { products: {} }
            prod_name = r['name']
            org_results[org_id][:products][prod_name] ||= 0
            org_results[org_id][:products][prod_name] += r['devices'].length
            total_devices += r['devices'].length
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
        data[:products].each do |prod_name, count|
          puts "  - #{prod_name}"
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

      client = NinjaOne::ClientWrapper.new(
        ENV.fetch('NINJA1_HOST'),
        ENV.fetch('NINJA1_CLIENT_ID'),
        ENV.fetch('NINJA1_CLIENT_SECRET'),
        false
      )

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

          vendor_results[vendor][:product_orgs][prod_name] ||= { count: 0, matched: matched, orgs: [] }

          r['organizations'].each do |org_id|
            vendor_results[vendor][:product_orgs][prod_name][:orgs] << org_id unless vendor_results[vendor][:product_orgs][prod_name][:orgs].include?(org_id)
            vendor_results[vendor][:product_orgs][prod_name][:count] += r['devices'].length
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
      total_devices = vendor_results.values.flat_map { |v| v[:product_orgs].values.map { |p| p[:count] } }.flatten.sum

      puts "Found #{total_orgs} organizations with #{total_devices} affected devices"
      puts

      vendor_results.each do |vendor, data|
        puts "Software found for vendor #{vendor}:"

        data[:product_orgs].each do |prod_name, prod_data|
          device_count = prod_data[:count]
          matched = prod_data[:matched]
          exclamation = matched ? '!!!' : '*'
          puts "#{exclamation} #{prod_name} (#{device_count} devices):"

          prod_data[:orgs].each do |org_id|
            org_name = get_org_name(client, org_id)
            puts "    - #{org_name}"
          end
        end
        puts
      end
    end
  end
end

MonitoringSoftware::CLI.run(ARGV) if __FILE__ == $PROGRAM_NAME
