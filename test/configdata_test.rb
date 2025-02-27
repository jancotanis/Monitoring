# frozen_string_literal: true

require 'test_helper'
require 'MonitoringConfig'

describe '#1 config data' do
  it '#1.1 ConfigData defaults' do
    cfg = ConfigData.new

    assert value(cfg.source).must_equal [], '1.1 empty source array'
    assert value(cfg.sla).must_equal [], '1.1 empty sla array'
    assert value(cfg.reported_alerts).must_equal [], '1.1 empty alerts array'
    assert value(cfg.notifications).must_equal [], '1.1 empty notifications array'
  end
  it '#1.2 ConfigData.monitoring?' do
    cfg = ConfigData.new

    assert !cfg.monitoring?, '1.2 must NOT be monitoring'

    cfg.create_ticket = true
    assert !cfg.monitoring?, '1.2 must NOT be monitoring'

    cfg.monitor_endpoints = true
    assert cfg.monitoring?, '1.2 must be monitoring'
    cfg.monitor_endpoints = false

    cfg.monitor_connectivity = true
    assert cfg.monitoring?, '1.2 must be monitoring'
    cfg.monitor_connectivity = false

    cfg.monitor_backup       = true
    assert cfg.monitoring?, '1.2 must be monitoring'
    cfg.monitor_backup       = false

    cfg.monitor_dtc          = true
    assert cfg.monitoring?, '1.2 must be monitoring'
  end
  it '#1.3 ConfigData.touch' do
    cfg = ConfigData.new

    assert !cfg.touched?, '1.3 must not be touched'

    new_cfg = cfg.touch
    assert cfg.touched?, '1.3 must be touched'
    assert _(cfg).must_equal(new_cfg), '1.3 touch return result should be self'

    new_cfg = cfg.untouch
    assert _(cfg).must_equal(new_cfg), '1.3 touch return result should be self'
    assert !cfg.touched?, '1.3 must not be touched'
  end
end
