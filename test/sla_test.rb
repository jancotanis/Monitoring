# frozen_string_literal: true

require 'test_helper'
require 'securerandom'
require 'MonitoringSLA'

describe '#3 SLA periods' do
  it '#3.1 weekly' do
    assert !WEEKLY.due?(Date.today)
    assert !WEEKLY.due?(Date.today - 1)
    assert WEEKLY.due?(Date.today - 7)
    assert WEEKLY.due?(Date.today - 100)
  end
  it '#3.2 monthly' do
    assert !MONTHLY.due?(Date.today)
    assert !MONTHLY.due?(Date.today - 1)
    assert MONTHLY.due?(Date.today - 30)
    assert MONTHLY.due?(Date.today - 100)
  end
  it '#3.3 quarterly' do
    assert !QUARTERLY.due?(Date.today)
    assert !QUARTERLY.due?(Date.today - 90)
    assert QUARTERLY.due?(Date.today - 91)
    assert QUARTERLY.due?(Date.today - 100)
  end
  it '#3.4 yearly' do
    assert !YEARLY.due?(Date.today)
    assert !YEARLY.due?(Date.today - 90)
    assert YEARLY.due?(Date.today - 365)
    assert YEARLY.due?(Date.today - 999)
  end
end
describe '#4 Notification' do
  it '#4.1 yearly' do
    TASK = 'Do something'
    DATE = '2025-02-04'
    notifications = Notification.new(TASK,MONTHLY.code, DATE)

    assert notifications.to_s["Task '#{TASK}'"], '4.1.1 task description'
    assert notifications.to_s["executed #{MONTHLY.description}"], '4.1.2 task interval'
    assert notifications.to_s["last time triggered #{DATE}"], '4.1.3 task trigger'

    notification = Notification.new(TASK,ONCE.code, DATE)
    assert notification.to_s["after date #{DATE}"], '4.1.4 task trigger once'

    notification = Notification.new(TASK, '?', DATE)
    assert notification.to_s["invalid interval='?'"], '4.1.5 invalid interval'
  end
end
describe '#5 SLA' do
  it '#5.1 SLA Instance' do
    MonitoringSLA.new(nil)
  end
  it '#5.2 SLA no config items/report' do
    FUTURE = Date.parse('2099-01-01')
    PAST = Date.parse('2000-01-01')

    cfg = MonitoringConfig.new

    # to clear config entries, untouch and compact because entries is viewonly...
    cfg.entries.each(&:untouch)
    cfg.compact!(true)

    sla = MonitoringSLA.new(cfg)
    assert _(sla.load_periodic_alerts).must_equal [], '5.2.1 no periodic notifications'
    assert _(sla.report_lines).must_equal [], '5.2.1 no report lines'

    entry = ConfigData.new(SecureRandom.uuid, 'no notifications')
    cfg.entries.push(entry)
    assert _(sla.load_periodic_alerts).must_equal [], '5.2.2 still no periodic notifications'

    entry = ConfigData.new(SecureRandom.uuid, 'very future notifications')
    entry.notifications.push(Notification.new('Test', MONTHLY.code, FUTURE))
    cfg.entries.push(entry)
    assert _(sla.load_periodic_alerts).must_equal [], '5.2.3  no future notifications'

    entry = ConfigData.new(SecureRandom.uuid, 'once very future notifications')
    entry.notifications.push(Notification.new('Test', ONCE.code, FUTURE))
    cfg.entries.push(entry)
    assert _(sla.load_periodic_alerts).must_equal [], '5.2.4  no future once notifications'

    assert _(sla.report_lines.count).must_equal 2, '5.2.4 two report lines'

    entry = ConfigData.new(SecureRandom.uuid, 'once past  notifications')
    entry.notifications.push(Notification.new('Test', ONCE.code, PAST))
    cfg.entries.push(entry)
    assert _(sla.report_lines.count).must_equal 3, '5.2.5 three report lines'
    assert _(sla.load_periodic_alerts.count).must_equal 1, '5.2.6  single past once notifications'
    assert _(sla.load_periodic_alerts).must_equal [], '5.2.7  once only once notifications'
    assert _(sla.report_lines.count).must_equal 2, '5.2.8 two report lines as once removed'
  end
end
