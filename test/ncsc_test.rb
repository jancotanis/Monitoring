# frozen_string_literal: true

require 'test_helper'
require 'MonitoringConfig'
require 'MonitoringNCSC'

class FeedNCSC < MonitoringNCSC
  def update_cache
    # prohibit changes to file system
  end

  def cache_name
    'ncsc-test.yml'
  end
end

describe '#1 CVEAlert' do
  it '#1.1 test CVE alert' do
    cve = CVEAlert.new('CVE-2025-27364')
    assert _(cve.score).must_equal 10, '1.1.1 CVE-2025-27364 score 10'

    cve = CVEAlert.new('CVE-2014-0064')
    assert _(cve.score).must_equal(-1), '1.1.1 CVE-2014-0064 unknown score'
  end
  it '#1.2 test non existing CVE alert' do
    cve = CVEAlert.new('XXX-2025-27364')
    assert cve.score.nil?, '1.2. cve xxx does not exist'
  end
end
describe '#2 NCSCTextAdvisory' do
  it '#2.1 test NCSC Advisory' do
    advisory = NCSCTextAdvisory.new('NCSC-2025-0001')
    assert _(advisory.id).must_equal 'NCSC-2025-0001', '2.1.1 2025-0001 loaded'
    assert _(advisory.cve.count).must_equal 3, '2.1.2 NCSC 2501 has 3 cve'
  end
  it '#2.2 test non existing CVE alert' do
    advisory = NCSCTextAdvisory.new('XXX-2025-001')
    assert _(advisory.cve).must_equal [], '2.2. NCSC xxx does not exist'
  end
end
describe '#3 NCSCFeed' do
  it '#3.1 test Feed Advisory fro new from now ' do
    feed = FeedNCSC.new(MonitoringConfig.new)

    list = feed.get_vulnerabilities_list(Time.new)
    assert _(list.count).must_equal 0, '3.1 should be no new items'
  end
  it '#3.2 test Feed Advisory' do
    feed = FeedNCSC.new(MonitoringConfig.new)

    list = feed.get_vulnerabilities_list(Time.new(0))
    assert list.any?, '3.2 should be new items'
  end
  it '#3.3 test check vulnerability description' do
    cfg = MonitoringConfig.new
    feed = FeedNCSC.new(cfg)
    company = cfg.entries.select { |comp| comp.monitor_dtc }.first
    list = feed.get_vulnerabilities_list
    assert list.any?, '3.3.1 should be new items'
    vulnerability = list.first
    assert vulnerability.description[company.description], "3.3.2 should include dtc sla company: #{company.description}"
  end
end
