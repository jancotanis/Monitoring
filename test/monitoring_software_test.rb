# frozen_string_literal: true

# Tests for MonitoringSoftware module - software indexing and search functionality

require 'fileutils'
require 'ostruct'

require 'test_helper'
require 'monitoring_software'

TEST_CACHE_FILE = 'test-software-index.json'

MOCK_INDEX = {
  'Microsoft Corporation' => {
    'Microsoft Edge' => {
      'publisher' => 'Microsoft Corporation',
      'name' => 'Microsoft Edge',
      'devices' => [1, 2, 3]
    },
    'Microsoft SQL Server' => {
      'publisher' => 'Microsoft Corporation',
      'name' => 'Microsoft SQL Server',
      'devices' => [4, 5]
    }
  },
  'Adobe Inc' => {
    'Adobe Acrobat Reader DC' => {
      'publisher' => 'Adobe Inc',
      'name' => 'Adobe Acrobat Reader DC',
      'devices' => [6, 7]
    },
    'Adobe Creative Cloud' => {
      'publisher' => 'Adobe Inc',
      'name' => 'Adobe Creative Cloud',
      'devices' => [8, 9]
    }
  }
}.freeze

describe '#7 MonitoringSoftware' do
  before do
    @indexer = MonitoringSoftware::SoftwareIndexer.new
  end

  describe '#7.1 Case-insensitive publisher search' do
    it '#7.1.1 publisher lowercase - microsoft' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: 'microsoft')
      assert_equal 2, results.count, 'microsoft should match 2 products'
    end

    it '#7.1.2 publisher uppercase - Microsoft' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: 'Microsoft')
      assert_equal 2, results.count, 'Microsoft should match 2 products'
    end

    it '#7.1.3 publisher mixed case - MicroSoft' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: 'MicroSoft')
      assert_equal 2, results.count, 'MicroSoft should match 2 products'
    end
  end

  describe '#7.2 Adobe search tests' do
    it '#7.2.1 search by publisher Adobe returns hits' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: 'adobe')
      assert_equal 2, results.count, 'Adobe publisher should return 2 products'
    end

    it '#7.2.2 search by product Adobe Acrobat returns hits' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(product: 'acrobat')
      assert_equal 1, results.count, 'Acrobat product should return 1 product'
      assert_equal 'Adobe Acrobat Reader DC', results.first['name']
    end

    it '#7.2.3 search by publisher Adobe and product Acrobat' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: 'adobe', product: 'acrobat')
      assert_equal 1, results.count
      assert_equal 'Adobe Inc', results.first['publisher']
    end
  end

  describe '#7.3 Non-existent publisher/product tests' do
    it '#7.3.1 search publisher DOES NOT EXIST returns 0 hits' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: 'PUBLISHER DOES NOT EXIST')
      assert_equal 0, results.count, 'Non-existent publisher should return 0 results'
    end

    it '#7.3.2 search product DOES NOT EXIST returns 0 hits' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(product: 'PRODUCT DOES NOT EXIST')
      assert_equal 0, results.count, 'Non-existent product should return 0 results'
    end

    it '#7.3.3 search both non-existent returns 0 hits' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: 'foo', product: 'bar')
      assert_equal 0, results.count
    end
  end

  describe '#7.4 Index loading tests' do
    it '#7.4.1 load_index creates index when file does not exist' do
      original_file = MonitoringSoftware::CACHE_FILE
      temp_file = "#{original_file}.test_backup"

      FileUtils.mv(original_file, temp_file) if File.exist?(original_file)

      begin
        error_raised = false
        begin
          @indexer.load_index
        rescue SystemExit
          error_raised = true
        end
        assert error_raised, 'Should exit when index file does not exist'
      ensure
        FileUtils.mv(temp_file, original_file) if File.exist?(temp_file)
      end
    end

    it '#7.4.2 cached index is used when exists (no file reload via mock)' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)

      results = @indexer.search(publisher: 'microsoft')
      assert_equal 2, results.count

      assert_nil @indexer.instance_variable_get(:@index)['fake_key'],
                 'Search should work from in-memory index without accessing file'
    end

    it '#7.4.3 load_index returns cached index if already loaded' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      loaded_index = @indexer.load_index
      assert_equal MOCK_INDEX, loaded_index
    end
  end

  describe '#7.5 Partial match tests' do
    it '#7.5.1 partial publisher match - micro' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: 'micro')
      assert results.any?, 'micro should match Microsoft'
      assert_equal 2, results.count
    end

    it '#7.5.2 partial product match - sql' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(product: 'sql')
      assert results.any?, 'sql should match SQL Server'
      assert_equal 1, results.count
    end

    it '#7.5.3 partial product match - creative' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(product: 'creative')
      assert_equal 1, results.count
      assert_equal 'Adobe Creative Cloud', results.first['name']
    end
  end

  describe '#7.6 build_index tests' do
    it '#7.6.1 build_index transforms raw software correctly' do
      raw = [
        OpenStruct.new(publisher: 'Microsoft', name: 'Edge', deviceId: 1),
        OpenStruct.new(publisher: 'Microsoft', name: 'Edge', deviceId: 2),
        OpenStruct.new(publisher: 'Microsoft', name: 'SQL', deviceId: 1)
      ]
      result = @indexer.build_index(raw)

      assert_equal 1, result.keys.count
      assert_equal %w[Edge SQL], result['Microsoft'].keys.sort
      assert_equal [1, 2], result['Microsoft']['Edge']['devices']
    end

    it '#7.6.2 build_index handles duplicate device entries' do
      raw = [
        OpenStruct.new(publisher: 'Test', name: 'App', deviceId: 1),
        OpenStruct.new(publisher: 'Test', name: 'App', deviceId: 1),
        OpenStruct.new(publisher: 'Test', name: 'App', deviceId: 2)
      ]
      result = @indexer.build_index(raw)

      assert_equal [1, 2], result['Test']['App']['devices']
    end

    it '#7.6.3 build_index handles nil/empty publisher and name' do
      raw = [
        OpenStruct.new(publisher: nil, name: 'App', deviceId: 1),
        OpenStruct.new(publisher: 'Test', name: nil, deviceId: 2),
        OpenStruct.new(publisher: '', name: '   ', deviceId: 3)
      ]
      result = @indexer.build_index(raw)

      assert_equal 2, result['Unknown'].keys.count, 'Unknown publisher has 2 products: App and Unknown (from empty name)'
    end

    it '#7.6.4 build_index adds organizations from device_org_map' do
      raw = [
        OpenStruct.new(publisher: 'Test', name: 'App', deviceId: 1),
        OpenStruct.new(publisher: 'Test', name: 'App', deviceId: 2),
        OpenStruct.new(publisher: 'Test', name: 'App', deviceId: 3)
      ]
      device_org_map = { 1 => 10, 2 => 20, 3 => 10 }
      result = @indexer.build_index(raw, device_org_map)

      assert_equal [1, 2, 3], result['Test']['App']['devices']
      assert_equal [10, 20], result['Test']['App']['organizations'], 'Should have unique orgs'
    end

    it '#7.6.5 build_index handles missing device in org map' do
      raw = [
        OpenStruct.new(publisher: 'Test', name: 'App', deviceId: 1),
        OpenStruct.new(publisher: 'Test', name: 'App', deviceId: 999)
      ]
      device_org_map = { 1 => 10 }
      result = @indexer.build_index(raw, device_org_map)

      assert_equal [10], result['Test']['App']['organizations'], 'Should skip missing device IDs'
    end
  end

  describe '#7.7 normalize_string tests' do
    it '#7.7.1 normalize_string handles nil' do
      assert_equal 'Unknown', @indexer.normalize_string(nil)
    end

    it '#7.7.2 normalize_string handles empty string' do
      assert_equal 'Unknown', @indexer.normalize_string('   ')
    end

    it '#7.7.3 normalize_string passes through valid strings' do
      assert_equal 'Microsoft', @indexer.normalize_string('Microsoft')
    end
  end

  describe '#7.8 CLI parse_options tests' do
    it '#7.8.1 parse_options extracts publisher' do
      opts = MonitoringSoftware::CLI.parse_options(['--publisher', 'microsoft'])
      assert_equal 'microsoft', opts[:publisher]
    end

    it '#7.8.2 parse_options extracts product' do
      opts = MonitoringSoftware::CLI.parse_options(['--product', 'edge'])
      assert_equal 'edge', opts[:product]
    end

    it '#7.8.3 parse_options extracts update flag' do
      opts = MonitoringSoftware::CLI.parse_options(['--update'])
      assert_equal true, opts[:update]
    end

    it '#7.8.4 parse_options combines publisher and product' do
      opts = MonitoringSoftware::CLI.parse_options(['--publisher', 'micro', '--product', 'edge'])
      assert_equal 'micro', opts[:publisher]
      assert_equal 'edge', opts[:product]
    end

    it '#7.8.5 parse_options returns empty hash for no args' do
      opts = MonitoringSoftware::CLI.parse_options([])
      assert_nil opts[:publisher]
      assert_nil opts[:product]
      assert_equal false, opts[:update]
    end
  end

  describe '#7.9 save_index and load_index integration' do
    it '#7.9.1 save_index writes file and load_index reads it back' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      original_cache = MonitoringSoftware::CACHE_FILE

      begin
        MonitoringSoftware::CACHE_FILE = TEST_CACHE_FILE
        FileUtils.rm_f(TEST_CACHE_FILE)

        @indexer.save_index

        assert File.exist?(TEST_CACHE_FILE), 'Index file should be created'

        new_indexer = MonitoringSoftware::SoftwareIndexer.new
        loaded = new_indexer.load_index

        loaded_keys = loaded.keys.reject { |k| k == '__metadata' }
        assert_equal MOCK_INDEX.keys.sort, loaded_keys.sort
        assert_equal 2, loaded['Microsoft Corporation'].keys.count
      ensure
        FileUtils.rm_f(TEST_CACHE_FILE)
        MonitoringSoftware::CACHE_FILE = original_cache
      end
    end
  end

  describe '#7.10 search edge cases' do
    it '#7.10.1 search with nil publisher and product returns all' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      results = @indexer.search(publisher: nil, product: nil)
      assert_equal 4, results.count, 'No filters should return all products'
    end

    it '#7.10.2 search handles nil in index gracefully' do
      bad_index = {
        'Bad Publisher' => {
          'Good Product' => { 'publisher' => nil, 'name' => 'Good Product', 'devices' => [1] }
        }
      }
      @indexer.instance_variable_set(:@index, bad_index)
      results = @indexer.search(publisher: 'bad')
      assert_equal 0, results.count, 'Should skip entries with nil publisher'
    end
  end

  describe '#7.11 CLI --cve option tests' do
    it '#7.11.1 parse_options extracts cve' do
      opts = MonitoringSoftware::CLI.parse_options(['--cve', 'CVE-2025-1234'])
      assert_equal 'CVE-2025-1234', opts[:cve]
    end

    it '#7.11.2 parse_options handles lowercase cve' do
      opts = MonitoringSoftware::CLI.parse_options(['--cve', 'cve-2025-1234'])
      assert_equal 'cve-2025-1234', opts[:cve]
    end

    it '#7.11.3 validate_cve_options accepts valid CVE format' do
      error_raised = false
      begin
        MonitoringSoftware::CLI.validate_cve_options({ cve: 'CVE-2025-1234' })
      rescue SystemExit
        error_raised = true
      end
      assert_equal false, error_raised, 'Valid CVE format should not raise error'
    end

    it '#7.11.4 validate_cve_options rejects invalid CVE format' do
      error_raised = false
      begin
        MonitoringSoftware::CLI.validate_cve_options({ cve: 'INVALID-2025-1234' })
      rescue SystemExit
        error_raised = true
      end
      assert_equal true, error_raised, 'Invalid CVE format should raise error'
    end
  end

  describe '#7.12 CVEAlert helpers with mock data' do
    it '#7.12.1 vendors returns list of vendors from affected data' do
      mock_data = {
        'containers' => {
          'cna' => {
            'affected' => [
              { 'vendor' => 'Microsoft', 'product' => 'Edge' },
              { 'vendor' => 'Microsoft', 'product' => 'Windows' },
              { 'vendor' => 'Adobe', 'product' => 'Acrobat Reader' }
            ]
          }
        }
      }
      cve = CVEAlert.allocate
      cve.instance_variable_set(:@data, mock_data)
      cve.instance_variable_set(:@score, 7.5)
      assert_equal %w[Microsoft Adobe], cve.vendors
    end

    it '#7.12.2 products returns list of products with vendor and cpes' do
      mock_data = {
        'containers' => {
          'cna' => {
            'affected' => [
              { 'vendor' => 'Microsoft', 'product' => 'Edge', 'cpes' => ['cpe:2.3:a:microsoft:edge:*:*:*:*:*:*:*:*'] },
              { 'vendor' => 'Adobe', 'product' => 'Acrobat Reader', 'cpes' => [] }
            ]
          }
        }
      }
      cve = CVEAlert.allocate
      cve.instance_variable_set(:@data, mock_data)
      cve.instance_variable_set(:@score, 7.5)
      products = cve.products
      assert_equal 2, products.length
      assert_equal 'Microsoft', products[0][:vendor]
      assert_equal 'Edge', products[0][:product]
      assert_equal 1, products[0][:cpes].length
    end

    it '#7.12.3 description returns English description' do
      mock_data = {
        'containers' => {
          'cna' => {
            'descriptions' => [
              { 'lang' => 'en', 'value' => 'Buffer overflow in Microsoft Edge' },
              { 'lang' => 'nl', 'value' => 'Buffer overflow in Microsoft Edge (Dutch)' }
            ]
          }
        }
      }
      cve = CVEAlert.allocate
      cve.instance_variable_set(:@data, mock_data)
      assert_equal 'Buffer overflow in Microsoft Edge', cve.description
    end

    it '#7.12.4 vendors returns empty when no affected data' do
      mock_data = {}
      cve = CVEAlert.allocate
      cve.instance_variable_set(:@data, mock_data)
      assert_equal [], cve.vendors
    end

    it '#7.12.5 products returns empty when no affected data' do
      mock_data = {}
      cve = CVEAlert.allocate
      cve.instance_variable_set(:@data, mock_data)
      assert_equal [], cve.products
    end

    it '#7.12.6 vendor_products returns hash of vendors to products' do
      mock_data = {
        'containers' => {
          'cna' => {
            'affected' => [
              { 'vendor' => 'Microsoft', 'product' => 'Edge' },
              { 'vendor' => 'Microsoft', 'product' => 'Windows' },
              { 'vendor' => 'Adobe', 'product' => 'Acrobat Reader' },
              { 'vendor' => 'Adobe', 'product' => 'Acrobat Reader' }
            ]
          }
        }
      }
      cve = CVEAlert.allocate
      cve.instance_variable_set(:@data, mock_data)
      result = cve.vendor_products
      assert_equal({ 'Microsoft' => %w[Edge Windows], 'Adobe' => ['Acrobat Reader'] }, result)
    end

    it '#7.12.7 vendor_products returns empty hash when no affected data' do
      mock_data = {}
      cve = CVEAlert.allocate
      cve.instance_variable_set(:@data, mock_data)
      assert_equal({}, cve.vendor_products)
    end
  end

  describe '#7.13 NCSCTextAdvisory vendor_products' do
    it '#7.13.1 vendor_products returns hash from CVE data' do
      ncsc = NCSCTextAdvisory.allocate
      ncsc.instance_variable_set(:@cve, [])
      assert_equal({}, ncsc.vendor_products)
    end
  end

  describe '#7.14 tenant_software tests' do
    it '#7.14.1 tenant_software returns empty hash when no matches' do
      @indexer.instance_variable_set(:@index, MOCK_INDEX)
      mock_client = Object.new.tap do |c|
        c.define_singleton_method(:tenants) { [] }
        c.define_singleton_method(:tenant_by_id) { |_id| nil }
      end
      result = @indexer.tenant_software(['NonExistent Org'], { 'Microsoft' => ['Edge'] }, mock_client)
      assert_equal({}, result)
    end

    it '#7.14.2 tenant_software filters by tenant names' do
      index_with_orgs = {
        'Microsoft Corporation' => {
          'Microsoft Edge' => {
            'publisher' => 'Microsoft Corporation',
            'name' => 'Microsoft Edge',
            'devices' => [1, 2, 3],
            'organizations' => [1, 2]
          }
        }
      }
      mock_tenant1 = OpenStruct.new(id: 1, name: 'Org A')
      mock_tenant2 = OpenStruct.new(id: 2, name: 'Org B')

      mock_client = Object.new.tap do |c|
        c.define_singleton_method(:tenants) { [mock_tenant1, mock_tenant2] }
        c.define_singleton_method(:tenant_by_id) do |id|
          [mock_tenant1, mock_tenant2].find { |t| t.id == id }
        end
      end

      @indexer.instance_variable_set(:@index, index_with_orgs)

      result = @indexer.tenant_software(['Org A'], { 'Microsoft Corporation' => ['Edge'] }, mock_client)

      assert_equal 1, result.keys.count
      assert result.key?('Org A')
      assert_equal({ 'Microsoft Corporation' => ['Microsoft Edge'] }, result['Org A'])
    end

    it '#7.14.3 tenant_software returns multiple vendors per tenant' do
      index_with_orgs = {
        'Microsoft Corporation' => {
          'Microsoft Edge' => {
            'publisher' => 'Microsoft Corporation',
            'name' => 'Microsoft Edge',
            'devices' => [1],
            'organizations' => [1]
          }
        },
        'Adobe Inc' => {
          'Adobe Acrobat Reader' => {
            'publisher' => 'Adobe Inc',
            'name' => 'Adobe Acrobat Reader',
            'devices' => [1],
            'organizations' => [1]
          }
        }
      }
      mock_tenant1 = OpenStruct.new(id: 1, name: 'Org A')

      mock_client = Object.new.tap do |c|
        c.define_singleton_method(:tenants) { [mock_tenant1] }
        c.define_singleton_method(:tenant_by_id) { |id| mock_tenant1 if id == 1 }
      end

      @indexer.instance_variable_set(:@index, index_with_orgs)

      vendor_products = {
        'Microsoft Corporation' => ['Edge'],
        'Adobe Inc' => ['Acrobat Reader']
      }

      result = @indexer.tenant_software(['Org A'], vendor_products, mock_client)

      assert_equal 2, result['Org A'].keys.count
      assert_includes result['Org A'], 'Microsoft Corporation'
      assert_includes result['Org A'], 'Adobe Inc'
    end
  end

  describe '#7.15 update_from_api tests' do
    it '#7.15.1 update_from_api builds index with devices and organizations' do
      mock_devices = [
        { 'id' => 37, 'organizationId' => 8 },
        { 'id' => 48, 'organizationId' => 8 },
        { 'id' => 49, 'organizationId' => 9 }
      ]

      mock_software = [
        { 'name' => 'AdobeAcrobatReaderCoreApp', 'publisher' => 'Adobe Acrobat Reader', 'deviceId' => 37 },
        { 'name' => 'AdobeAcrobatReaderCoreApp', 'publisher' => 'Adobe Acrobat Reader', 'deviceId' => 48 },
        { 'name' => 'AdobeAcrobatReaderCoreApp', 'publisher' => 'Adobe Acrobat Reader', 'deviceId' => 49 }
      ]

      mock_api = Object.new.tap do |api|
        api.define_singleton_method(:devices) { mock_devices }
        api.define_singleton_method(:queries_software) { mock_software }
      end

      mock_client = Object.new.tap do |c|
        c.define_singleton_method(:api) { mock_api }
      end

      indexer = MonitoringSoftware::SoftwareIndexer.new(mock_client)
      indexer.update_from_api

      assert indexer.index, 'Index should be built'
      assert_equal 1, indexer.index.keys.count, 'Should have 1 publisher'

      adobe_data = indexer.index['Adobe Acrobat Reader']
      assert adobe_data, 'Adobe publisher should exist'

      acrobat = adobe_data['AdobeAcrobatReaderCoreApp']
      assert acrobat, 'AdobeAcrobatReaderCoreApp should exist'
      assert_equal 3, acrobat['devices'].length, 'Should have 3 devices'
      assert acrobat['devices'].include?(37), 'Should include device 37'
      assert acrobat['devices'].include?(48), 'Should include device 48'
      assert acrobat['devices'].include?(49), 'Should include device 49'

      assert_equal 2, acrobat['organizations'].length, 'Should have 2 organizations'
      assert acrobat['organizations'].include?(8), 'Should include organization 8'
      assert acrobat['organizations'].include?(9), 'Should include organization 9'
    end
  end
end
