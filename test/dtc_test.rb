# frozen_string_literal: true

require 'test_helper'
require 'MonitoringConfig'
require 'MonitoringDTC'

class FeedDTC < MonitoringDTC
  def update_cache
    # prohibit changes to file system
  end

  def cache_name
    'ncsc-test.yml'
  end
end

describe '#3 DTCFeed' do
  it '#3.1 test Feed Advisory fro new from now ' do
    feed = FeedDTC.new(MonitoringConfig.new)

    list = feed.get_vulnerabilities_list(Time.new)
    assert _(list.count).must_equal 0, '3.1 should be no new items'
  end
  it '#3.2 test Feed Advisory' do
    feed = FeedDTC.new(MonitoringConfig.new)

    list = feed.get_vulnerabilities_list(Time.new(0))
    assert list.any?, '3.2 should be new items'
  end
  it '#3.3 test check vulnerability description' do
    cfg = MonitoringConfig.new
    feed = FeedDTC.new(cfg)
    company = cfg.entries.select(&:monitor_dtc).first
    list = feed.get_vulnerabilities_list
    assert list.any?, '3.3.1 should be new items'
    vulnerability = list.first
    assert vulnerability.description[company.description],
           "3.3.2 should include dtc sla company: #{company.description}"
  end
end
