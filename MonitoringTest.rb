# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'Date'
require_relative 'MonitoringConfig'
require_relative 'MonitoringSLA'

TenantMock = Struct.new(:id, :description, :endpoints, :trial?)
TestStruct = Struct.new(:raw_data)

describe '#1 config' do
  before do
    @cfg = MonitoringConfig.new
  end

  it '#1.1 load' do
    begin
      @cfg.load_config('Test', [])
      company = 'VDH Company B.V.'
      assert value(@cfg.by_description(company).description).must_equal company, '1.1.1 load []; not adding'
      company = 'Test Company'
      assert_nil @cfg.by_description(company), '1.2 load []; no test company'
      @cfg = MonitoringConfig.new
      @cfg.load_config('Test', [TenantMock.new('0', company, [], false)])
      assert value(@cfg.by_description(company).description).must_equal company, '1.1.3 load []; adding test comp'
      @cfg.delete_entry @cfg.by_description(company)
      assert_nil @cfg.by_description(company), '1.4 cfg delete entry'
      @cfg.save_config
    end
  end
  it '#1.2 find by name' do
    begin
      company = 'VDH Company B.V.'
      @cfg = MonitoringConfig.new
      @cfg.load_config('Test', [])
      assert value(@cfg.by_description(company).description).must_equal company, '1.2.1 check find by company'
    end
  end
end

describe '#2 utils' do
  it '#2.1.1 FileUtils' do
    assert value(FileUtil.daily_file_name('error.log')).must_equal "error-#{FileUtil.timestamp}.log", '2.1.1 daily name'
  end
  it '#2.1.2 FileUtils' do
    assert value(FileUtil.daily_module_name('')).must_equal "string-#{FileUtil.timestamp}.log", '2.1.2 daily module name'
  end
  it '#2.2 Struct' do
    string = '{"id":"id-0", "desc":{"someKey":"someValue","anotherKey":"value"},"main_item":{"stats":{"a":8,"b":12,"c":10}}}'
    t = TestStruct.new(JSON.parse(string))
    assert value(t.property('key')).must_equal '', '2.2.1 property not exist'
    assert value(t.property('id')).must_equal 'id-0', '2.2.1 property '
    assert value(t.property('desc.someKey')).must_equal 'someValue', '2.2.1 nested property'
    assert value(t.property('main_item.stats.a')).must_equal '8', '2.2.1 nested property'
  end
end

describe '#3 SLA periods' do
  it '#3.1 weekly' do
    assert !WEEKLY.due?(Date.today)
    assert !WEEKLY.due?(Date.today - 1)
    assert WEEKLY.due?(Date.today - 7)
    assert WEEKLY.due?(Date.today - 100)
  end
  it '#3.1 monthly' do
    assert !MONTHLY.due?(Date.today)
    assert !MONTHLY.due?(Date.today - 1)
    assert MONTHLY.due?(Date.today - 30)
    assert MONTHLY.due?(Date.today - 100)
  end
  it '#3.1 quarterly' do
    assert !QUARTERLY.due?(Date.today)
    assert !QUARTERLY.due?(Date.today - 90)
    assert QUARTERLY.due?(Date.today - 91)
    assert QUARTERLY.due?(Date.today - 100)
  end
  it '#3.1 yearly' do
    assert !YEARLY.due?(Date.today)
    assert !YEARLY.due?(Date.today - 90)
    assert YEARLY.due?(Date.today - 365)
    assert YEARLY.due?(Date.today - 999)
  end
end
