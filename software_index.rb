# frozen_string_literal: true

require 'json'

require_relative 'ninjaone_api'

module MonitoringSoftware
  CACHE_FILE = 'software-index.json'

  class SoftwareIndexer
    attr_reader :index, :index_updated_at

    def initialize(client = nil)
      @index = nil
      @devices = nil
      @client = client
    end

    def client
      @client ||= NinjaOne::ClientWrapper.new(
        ENV.fetch('NINJA1_HOST'),
        ENV.fetch('NINJA1_CLIENT_ID'),
        ENV.fetch('NINJA1_CLIENT_SECRET'),
        false
      )
    end

    def update_from_api
      puts 'Fetching software from NinjaOne API...'

      puts 'Fetching device organization mapping...'
      device_map = fetch_device_map(client)
      puts "Found #{device_map.keys.count} devices"
      raw = client.api.queries_software
      puts "Retrieved #{raw.count} software entries"
      @index = build_index(raw, device_map)
      @devices = device_map
      save_index

      puts "Index saved to #{CACHE_FILE}"
      puts "Indexed #{@index.keys.count} publishers"

      @index
    end

    # Returns device_id => { id, hostname, organization_id }
    def fetch_device_map(client)
      devices = client.api.devices

      mapping = {}

      devices.each do |device|
        device_id = device.id
        org_id = device.organizationId
        next if device_id.nil?

        mapping[device_id] = {
          'id' => device_id,
          'hostname' => device.systemName,
          'organization_id' => org_id
        }
      end

      mapping
    end

    def build_index(raw_software, device_map = {})
      indexed = {}


      raw_software.each do |sw|
        pub = name = normalize_string(sw.name)
        begin
          pub = normalize_string(sw.publisher)
        rescue => e
          # sometimes publisher not available, in that case keep software name as publisher
        end
        device_id = sw.deviceId

        indexed[pub] ||= {}
        indexed[pub][name] ||= {
          'publisher' => pub,
          'name' => name,
          'devices' => [],
          'organizations' => []
        }
        indexed[pub][name]['devices'] << device_id if device_id
      end

      indexed.each_value do |products|
        products.each_value do |data|
          data['devices'].compact!
          data['devices'].uniq!
          data['devices'].sort!
          data['organizations'] = data['devices'].map { |d| device_map[d] && device_map[d]['organization_id'] }.compact.uniq.sort
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

      parsed = JSON.parse(File.read(CACHE_FILE))
      @devices = parsed['devices'] || {}
      @index = parsed['software'] || {}
    end

    def save_index
      require 'time'

      payload = {
        'devices' => @devices || {},
        'software' => @index || {},
        '__metadata' => {
          'updated_at' => Time.now.iso8601
        }
      }

      File.write(CACHE_FILE, JSON.pretty_generate(payload))
    end

    def search(publisher: nil, product: nil)
      load_index

      @index_updated_at = @index.dig('__metadata', 'updated_at')

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

    # Returns device objects for matching software
    def devices_for(publisher: nil, product: nil)
      load_index

      results = search(publisher: publisher, product: product)

      results.flat_map do |r|
        (r['devices'] || []).map do |id|
          @devices[id.to_s] || @devices[id]
        end
      end.compact.uniq { |d| d['id'] }
    end

    def tenant_software(tenant_names, vendor_products, client = nil)
      load_index

      client ||= self.client

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
end
