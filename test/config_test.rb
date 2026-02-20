# frozen_string_literal: true

require 'test_helper'
require 'MonitoringConfig'

TenantMock = Struct.new(:id, :description, :endpoints, :trial?)
TEST_ID = 'test-untouched_item'

describe '#1 config' do
  before do
    @cfg = MonitoringConfig.new
  end

  it '#1.1 load' do
    @cfg.load_config('Test', [])
    company = 'VDH Company B.V.'
    assert value(@cfg.by_description(company).description).must_equal company, '1.1.1 load []; not adding'

    company = 'Test Company'
    assert_nil @cfg.by_description(company), '1.1.2 load []; no test company'

    @cfg = MonitoringConfig.new
    @cfg.load_config('Test', [TenantMock.new('0', company, [], false)])
    assert value(@cfg.by_description(company).description).must_equal company, '1.1.3 load []; adding test comp'

    @cfg.delete_entry @cfg.by_description(company)
    assert_nil @cfg.by_description(company), '1.1.4 cfg delete entry'
  end
  it '#1.2 find by name' do
    company = 'VDH Company B.V.'
    assert value(@cfg.by_description(company).description).must_equal company, '1.2.1 check find by name'
  end
  it '#1.3 find by id' do
    company = 'VDH Company B.V.'
    vdh = @cfg.by_description(company)
    assert value(vdh).must_equal @cfg.by_id(vdh.id), '1.3.1 check find by id'
  end
  it '#1.4 check absent config file' do
    tmp = "#{MONITORING_CFG}.test"
    FileUtils.rm_f(tmp)
    File.rename(MONITORING_CFG, tmp)
    cfg = MonitoringConfig.new
    assert _(cfg.entries).must_equal [], '1.4 empty config entries'
    FileUtils.rm_f(MONITORING_CFG)
    # back to normal
    File.rename(tmp, MONITORING_CFG)
  end
  it '#1.5 run report' do
    # touch remaining code
    FileUtils.rm_f(MONITORING_REPORT)
    # report silent so no console output
    @cfg.report(true)
    assert File.exist?(MONITORING_REPORT), '1.5 report should be present'
  end
  it '#1.6 compact' do
    # touchall
    @cfg.entries.each(&:touch)
    count = @cfg.entries.count
    @cfg.compact!
    assert _(@cfg.entries.count).must_equal count, '1.6.1 compact should not differ'

    # add none touched entry
    @cfg.load_config('test', [TenantMock.new(TEST_ID, 'untouched entry')])

    new_entry = @cfg.by_id(TEST_ID)
    assert new_entry.touched?, '1.6.2 check if touched because by_id() entry added '

    new_entry.untouch
    assert !new_entry.touched?, '1.6.3 check if touched because by_id() entry added '

    assert @cfg.entries.count > count, '1.6.4 untouched entry added'
    @cfg.compact!
    assert _(@cfg.entries.count).must_equal count, '1.6.4 compact should be equal again'
  end
end
