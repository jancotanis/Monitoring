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
  it '#1.7 fingerprint matching' do
    company = 'VDH Company B.V.'
    assert value(@cfg.by_description(company).description).must_equal company, '1.7.1 exact match still works'

    # fingerprint match: same name without dots/spacing
    found = @cfg.by_description('VDH Company BV')
    assert value(found.description).must_equal company, '1.7.2 fingerprint match B.V. vs BV'

    # fingerprint match: different case
    found = @cfg.by_description('vdh company b.v.')
    assert value(found.description).must_equal company, '1.7.3 fingerprint match case insensitive'
  end
  it '#1.8 load_config fingerprint dedup' do
    variant_desc = 'VDH Company BV'
    original_count = @cfg.entries.count

    # load a tenant with a slightly different name (no dots)
    @cfg.load_config('TestFingerprint', [TenantMock.new('new-id', variant_desc)])
    found = @cfg.by_description(variant_desc)
    assert found, '1.8.1 fingerprint dedup finds merged entry'

    # should not add a new entry
    assert _(@cfg.entries.count).must_equal original_count, '1.8.2 no new entry created'

    # source should be added
    assert found.source.include?('TestFingerprint'), '1.8.3 source added to merged entry'

    # cleanup
    @cfg.delete_entry(found)
  end
end

describe '#2 find_duplicates' do
  before do
    @cfg = MonitoringConfig.new
    # assume duplicates so add first entry as duplicate to the end
    dup = @cfg.entries.first.clone
    dup.description += '.'
    @cfg.entries << dup
  end

  it '#2.1 finds duplicate entries' do
    dupes = @cfg.find_duplicates
    _(dupes.size).must_be :>, 0, '2.1.1 should find duplicates in real config'
    dupes.each do |group|
      _(group.size).must_be :>, 1, '2.1.2 each group has >1 entry'
    end
  end

  it '#2.2 groups entries by fingerprint' do
    dupes = @cfg.find_duplicates
    dupes.each do |group|
      fingerprints = group.map { |e| MonitoringTenant.fingerprint(e.description) }.uniq
      _(fingerprints.size).must_equal 1, "2.2.1 all entries in group share fingerprint: #{group.map(&:description)}"
    end
  end
end

describe '#3 merge_group' do
  before do
    @cfg = MonitoringConfig.new
  end

  it '#3.1 merges sources from duplicates' do
    dupes = @cfg.find_duplicates
    skip('no duplicates to test') if dupes.empty?

    group = dupes.first
    all_sources = group.flat_map(&:source).uniq
    canonical = @cfg.merge_group(group)

    _(canonical.source.sort).must_equal all_sources.sort, '3.1.1 merged sources contain all original sources'
  end

  it '#3.2 removes duplicates after merge' do
    dupes = @cfg.find_duplicates
    skip('no duplicates to test') if dupes.empty?

    group = dupes.first
    count_before = @cfg.entries.count
    removed = group.size - 1
    @cfg.merge_group(group)

    _(@cfg.entries.count).must_equal count_before - removed, '3.2.1 duplicates removed after merge'
  end

  it '#3.3 keeps the entry with most sources as canonical' do
    dupes = @cfg.find_duplicates
    skip('no duplicates to test') if dupes.empty?

    group = dupes.first
    expected_canonical = group.max_by { |e| [e.source.size, e.description.length] }
    canonical = @cfg.merge_group(group)

    _(canonical).must_equal expected_canonical, '3.3.1 canonical has most sources'
  end

  it '#3.4 merges monitoring flags with true wins' do
    dupes = @cfg.find_duplicates
    skip('no duplicates to test') if dupes.empty?

    group = dupes.first
    any_ticket = group.any?(&:create_ticket)
    any_endpoints = group.any?(&:monitor_endpoints)
    any_backup = group.any?(&:monitor_backup)
    any_connectivity = group.any?(&:monitor_connectivity)
    any_dtc = group.any?(&:monitor_dtc)
    canonical = @cfg.merge_group(group)

    _(canonical.create_ticket).must_equal any_ticket, '3.4.1 create_ticket merged correctly'
    _(canonical.monitor_endpoints).must_equal any_endpoints, '3.4.2 monitor_endpoints merged correctly'
    _(canonical.monitor_backup).must_equal any_backup, '3.4.3 monitor_backup merged correctly'
    _(canonical.monitor_connectivity).must_equal any_connectivity, '3.4.4 monitor_connectivity merged correctly'
    _(canonical.monitor_dtc).must_equal any_dtc, '3.4.5 monitor_dtc merged correctly'
  end
end
