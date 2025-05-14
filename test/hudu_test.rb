# frozen_string_literal: true

require 'test_helper'
require 'hudu_test_data'
require 'hudu_dashboard'
require 'hudu_matcher'

KNOWN_SERVICE = Services::SKYKICK
UNKNOWN_SERVICE = 'mykick'
EXAMPLE_COM = 'http://example.com'
DASH_API = 'http://api.example.com/magic_dash'

PortalCompany = Struct.new(:description, :touched) do
  def touch
    touched = true
  end

  def touched?
    touched
  end
end

Portal = Struct.new(:entries) do
  def by_description(name)
    entries.select { |cfg| cfg.description.eql? name }&.first
  end
end
HuduCompany = Struct.new(:name)

describe '#1 Hudu Enums' do
  it '#1.1 actions' do
    assert _(Actions::ACTIONS.count).must_equal 3, '#1.1 3 known actions'
  end
  it '#1.2 services' do
    assert _(Services::KNOWN_SERVICES.count).must_equal(7), '#1.2.1 7 known services'
    assert Services.known_service?(KNOWN_SERVICE), '#1.2.2 known service '
    refute Services.known_service?(UNKNOWN_SERVICE), '#1.2.3 unknown services '
    refute Services.url(KNOWN_SERVICE).empty?, '#1.2.4 known service url'
    assert Services.url(UNKNOWN_SERVICE).to_s.empty?, '#1.2.5 no service url'
  end
end
describe '#2 Hudu Asset Layout' do
  it '#2.1 create layout' do
    al = AssetLayout.create(LAYOUT_TEST_JSON, true)
    assert _(LAYOUT_TEST_JSON.fields.count).must_equal 4, '#2.1.1 4 fields test data'
    assert _(al.fields.count).must_equal 2, '#2.1.2 2 fields in layout'
    assert _(al.custom_fields.count).must_equal(al.fields.count * 3), '#2.1.3 2 fields in layout, 6 in custom layout'
    refute al.fields.first.value, '#2.1.4 value should be false for templates'
  end
  it '#2.2 create assets' do
    al = AssetLayout.create(ASSET_TEST_JSON)
    assert _(ASSET_TEST_JSON.fields.count).must_equal 3, '#2.2.1 3 fields test data'
    assert _(al.fields.count).must_equal 1, '#2.2.2 2 fields in layout'
    assert _(al.custom_fields.count).must_equal(al.fields.count * 3), '#2.2.3 2 fields in layout, 6 in custom layout'

    asset = al.fields.first

    assert _(asset.value).must_equal("#{asset.label}:#{Actions::ENABLED}"), '#2.2.4 custom field/value equal'
    assert _(asset.note).must_equal("#{asset.label}:#{Actions::NOTE}"), '#2.2.5 custom field/value equal'
    assert _(asset.url).must_equal("#{asset.label}:#{Actions::URL}"), '#2.2.6 custom field/value equal'

    custom_fields = al.custom_fields
    custom_fields.each do |field|
      assert _(field.value).must_equal(field.label), '#2.2.4 custom field/value equal'
    end

    custom = custom_fields.first
    assert _(asset.value).must_equal(custom.label), '#2.2.5 value should be eequals to label for test data'
  end
  it '#2.3 update asset' do
    al = AssetLayout.create(LAYOUT_TEST_JSON, true)
    assert_raises(StandardError) do
      al.update_asset(nil)
    end
  end
end
describe DashBuilder do
  let(:client) { mock('client') }
  let(:builder) { DashBuilder.new(client) }
  let(:asset) { mock('asset') }
  let(:layout) { mock('AssetLayout') }
  let(:service_enabled) { mock('service_enabled') }
  let(:service_disabled) { mock('service_disabled') }

  before do
    AssetLayout.stubs(:create).with(asset).returns(layout)
    asset.stubs(:company_name).returns('Company name')
    service_enabled.stubs(:type).returns(Actions::ENABLED)
    service_enabled.stubs(:label).returns('Monitoring')
    service_enabled.stubs(:value).returns('Active')
    service_enabled.stubs(:note).returns('All systems operational')
    service_enabled.stubs(:url).returns(EXAMPLE_COM)

    service_disabled.stubs(:type).returns('DISABLED')

    layout.stubs(:fields).returns([service_enabled, service_disabled])
  end

  describe '#create_dash_from_asset' do
    it 'posts an entry for enabled services' do
      expected_dash = {
        'title' => 'Monitoring',
        'company_name' => asset.company_name,
        'content_link' => EXAMPLE_COM,
        'shade' => 'success',
        'message' => 'All systems operational'
      }

      client.expects(:api_url).with('magic_dash').returns(DASH_API)
      client.expects(:post).with(DASH_API, expected_dash)

      builder.create_dash_from_asset(asset)
    end

    it 'skips services that are not enabled' do
      service_enabled.stubs(:type).returns('DISABLED')
      client.expects(:post).never

      builder.create_dash_from_asset(asset)
    end

    it 'sets grey color and default message if service value and note are empty' do
      service_enabled.stubs(:value).returns(nil)
      service_enabled.stubs(:note).returns('')

      expected_dash = {
        'title' => 'Monitoring',
        'company_name' => asset.company_name,
        'content_link' => EXAMPLE_COM,
        'shade' => 'gray',
        'message' => Services::NO_SERVICE_TEXT
      }

      client.expects(:api_url).with('magic_dash').returns(DASH_API)
      client.expects(:post).with(DASH_API, expected_dash)

      builder.create_dash_from_asset(asset)
    end
  end
end
describe '#4 Hudu Matcher' do
  it '#4.1 Create empty Matcher' do
    matcher = Matcher.new([], [])
    assert matcher, '#4.1 should not be nil'
    assert _(matcher.matches.count).must_equal 0, '#4.1.1 no matches'
    assert _(matcher.nonmatches.count).must_equal 0, '#4.1.2 no nonmatches'
  end
  it '#4.2 Create no matches' do
    portal = Portal.new([PortalCompany.new('d')])
    hudu = ['a', 'b', 'c'].inject([]) { |a, o| a.push(HuduCompany.new(o)) }
    matcher = Matcher.new(hudu, portal)
    assert _(matcher.matches.count).must_equal 0, '#4.2.1 no matches'
    assert _(matcher.nonmatches.count).must_equal hudu.count, '#4.2.2 all nonmatches'
  end
  it '#4.3 Create single matches' do
    portal = Portal.new([PortalCompany.new('a'), PortalCompany.new('d')])
    hudu = ['a', 'b', 'c'].inject([]) { |a, o| a.push(HuduCompany.new(o)) }
    matcher = Matcher.new(hudu, portal)
    assert _(matcher.matches.count).must_equal 1, '#4.3.1 single matches'
    assert _(matcher.nonmatches.count).must_equal(hudu.count - 1), '#4.3.2 all nonmatches'
  end
  it '#4.4 Create single and partial matches' do
    portal = Portal.new([PortalCompany.new('a'), PortalCompany.new('d')])
    hudu = ['a', 'b', 'c', 'partial found'].inject([]) { |a, o| a.push(HuduCompany.new(o)) }
    matcher = Matcher.new(hudu, portal)
    assert _(matcher.matches.count).must_equal 2, '#4.4.1 single matches'
    assert _(matcher.nonmatches.count).must_equal(hudu.count - 2), '#4.4.2 all nonmatches'
  end
end
