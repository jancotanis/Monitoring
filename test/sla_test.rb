# frozen_string_literal: true

require 'test_helper'
require 'securerandom'
require 'MonitoringSLA'

TASK = 'Do something'
DATE = '2025-02-04'
FUTURE = Date.parse('2099-01-01')
PAST = Date.parse('2000-01-01')
CUSTOMER_A = 'Customer A'
UNKNOWN_CUSTOMER = 'Unknown Customer'
BACKUP_TASK = 'Backup task'

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
    notifications = Notification.new(TASK, MONTHLY.code, DATE)

    assert notifications.to_s["Task '#{TASK}'"], '4.1.1 task description'
    assert notifications.to_s["executed #{MONTHLY.description}"], '4.1.2 task interval'
    assert notifications.to_s["last time triggered #{DATE}"], '4.1.3 task trigger'

    notification = Notification.new(TASK, ONCE.code, DATE)
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
    assert _(sla.report_lines.count).must_equal(2 + 2), '5.2.5 two company + two report lines'

    entry = ConfigData.new(SecureRandom.uuid, 'once past  notifications')
    entry.notifications.push(Notification.new('Test', ONCE.code, PAST))
    cfg.entries.push(entry)
    assert _(sla.report_lines.count).must_equal(3 + 3), '5.2.6 three report lines'
    assert _(sla.load_periodic_alerts.count).must_equal 1, '5.2.7  single past once notifications'
    assert _(sla.load_periodic_alerts).must_equal [], '5.2.8  once only once notifications'
    assert _(sla.report_lines.count).must_equal(2 + 2), '5.2.9 two report lines as once removed'
  end
end
describe MonitoringSLA do
    let(:config) { mock('config') }
    let(:sla) { MonitoringSLA.new(config) }
  before do
    # Mock configuration setup
    @mock_notifications = []
    @config_entry = Struct.new(:description, :notifications, :create_ticket)\
                          .new(CUSTOMER_A, @mock_notifications, false)
    @config = Minitest::Mock.new
    @config = Object.new
    @config.stubs(:entries).returns([@config_entry])

    @sla = MonitoringSLA.new(@config)
  end

  describe '#load_periodic_alerts' do
    it 'triggers due notifications based on their intervals' do
      notification = Notification.new(BACKUP_TASK, 'W', Date.today - 8)
      @config_entry.notifications << notification

      alerts = @sla.load_periodic_alerts

      _(alerts.size).must_equal 1
      _(alerts.first.notification.task).must_equal BACKUP_TASK
      _(alerts.first.interval).must_equal WEEKLY
      _(alerts.first.description).must_match(/to be executed Weekly/)
    end

    it 'does not trigger notifications that are not yet due' do
      notification = Notification.new(BACKUP_TASK, 'W', Date.today - 3)
      @config_entry.notifications << notification

      alerts = @sla.load_periodic_alerts

      _(alerts).must_be_empty
    end

    it 'triggers and removes one-time notifications' do
      notification = Notification.new('One-time task', 'O', nil)
      @config_entry.notifications << notification

      alerts = @sla.load_periodic_alerts

      _(alerts.size).must_equal 1
      _(alerts.first.interval).must_equal ONCE
      _(@config_entry.notifications).must_be_empty
    end

    it 'does not trigger notifications with invalid intervals' do
      notification = Notification.new('Invalid interval task', 'Z', Date.today)
      @config_entry.notifications << notification
      @config.stubs(:by_description).with(UNKNOWN_CUSTOMER).returns(nil)

      alerts = @sla.load_periodic_alerts

      _(alerts).must_be_empty
    end
  end
  describe '#add_interval_notification' do
    before do
      @config.stubs(:by_description).with(CUSTOMER_A).returns(@config_entry)
      @config.stubs(:save_config).returns(nil)
    end

    it 'adds a valid interval notification with a correct date' do
      date = '2024-01-01'
      @sla.add_interval_notification(CUSTOMER_A, 'Backup check', 'W', date)

      _(@mock_notifications.size).must_equal 1
      notification = @mock_notifications.first
      _(notification.task).must_equal 'Backup check'
      _(notification.interval).must_equal 'W'
      _(notification.triggered).must_equal Date.parse(date)
      _(@config_entry.create_ticket).must_equal true
    end
    it 'adds a valid interval notification without a date' do
      @sla.add_interval_notification(CUSTOMER_A, 'Database backup', 'M')

      _(@mock_notifications.size).must_equal 1
      notification = @mock_notifications.first
      _(notification.task).must_equal 'Database backup'
      _(notification.interval).must_equal 'M'
      _(notification.triggered).must_be_nil
    end

    it 'does not add a notification with an invalid interval' do
      invalid_interval = 'Z'
      out, _ = capture_io do
        @sla.add_interval_notification(CUSTOMER_A, 'Invalid task', invalid_interval)
      end

      _(@mock_notifications).must_be_empty
      _(out).must_include "'#{invalid_interval}' is not a valid interval"
    end

    it 'does not add a notification if the customer is not found' do
      # Mock a "nil" response for a missing customer
      @config.stubs(:by_description).with(UNKNOWN_CUSTOMER).returns(nil)
      out, _ = capture_io do
        @sla.add_interval_notification(UNKNOWN_CUSTOMER, 'Task', 'W')
      end

      _(out).must_include "customer '#{UNKNOWN_CUSTOMER}' not found in configuration"
    end

    it 'handles invalid date parsing and displays an error message' do
      invalid_date = 'invalid-date'
      out, _ = capture_io do
        @sla.add_interval_notification(CUSTOMER_A, 'Task with bad date', 'W', invalid_date)
      end

      _(@mock_notifications).must_be_empty
      _(out).must_include "'#{invalid_date}' is not a valid date"
    end

  end
  describe '#report_lines' do
    it 'returns report lines for configs with notifications' do
      cfg1 = mock('cfg1')
      cfg1.stubs(:notifications).returns(['Alert 1', 'Alert 2'])
      cfg1.stubs(:description).returns('Customer A')

      cfg2 = mock('cfg2')
      cfg2.stubs(:notifications).returns([])
      cfg2.stubs(:description).returns('Customer B')

      cfg3 = mock('cfg3')
      cfg3.stubs(:notifications).returns(['Only One'])
      cfg3.stubs(:description).returns('Customer C')

      config.stubs(:entries).returns([cfg1, cfg2, cfg3])

      expected = [
        'Customer A',
        '- Alert 1',
        '- Alert 2',
        'Customer C',
        '- Only One'
      ]

      assert_equal expected, sla.report_lines
    end

    it 'returns an empty array if no config entries have notifications' do
      cfg = mock('cfg')
      cfg.stubs(:notifications).returns([])
      config.stubs(:entries).returns([cfg])

      assert_equal [], sla.report_lines
    end

    it 'skips configs with nil notifications' do
      cfg = mock('cfg')
      cfg.stubs(:notifications).returns(nil)
      config.stubs(:entries).returns([cfg])

      assert_equal [], sla.report_lines
    end
  end
end
