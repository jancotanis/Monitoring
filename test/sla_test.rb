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
  before do
    # Mock configuration setup
    @mock_notifications = []
    @config_entry = Struct.new(:description, :notifications, :create_ticket).new('Customer A', @mock_notifications, false)
    @config = Minitest::Mock.new
    @config = Object.new
    @config.stubs(:entries).returns([@config_entry])

    @sla = MonitoringSLA.new(@config)
  end

  describe '#load_periodic_alerts' do
    it 'triggers due notifications based on their intervals' do
      notification = Notification.new('Backup task', 'W', Date.today - 8)
      @config_entry.notifications << notification

      alerts = @sla.load_periodic_alerts

      _(alerts.size).must_equal 1
      _(alerts.first.notification.task).must_equal 'Backup task'
      _(alerts.first.interval).must_equal WEEKLY
      _(alerts.first.description).must_match(/to be executed Weekly/)
    end

    it 'does not trigger notifications that are not yet due' do
      notification = Notification.new('Backup task', 'W', Date.today - 3)
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
      @config.stubs(:by_description).with('Unknown Customer').returns(nil)

      alerts = @sla.load_periodic_alerts

      _(alerts).must_be_empty
    end
  end
  describe '#add_interval_notification' do
    before do
      @config.stubs(:by_description).with('Customer A').returns(@config_entry)
      @config.stubs(:save_config).returns(nil)
    end

    it 'adds a valid interval notification with a correct date' do
      date = '2024-01-01'
      @sla.add_interval_notification('Customer A', 'Backup check', 'W', date)

      _( @mock_notifications.size ).must_equal 1
      notification = @mock_notifications.first
      _( notification.task ).must_equal 'Backup check'
      _( notification.interval ).must_equal 'W'
      _( notification.triggered ).must_equal Date.parse(date)
      _(@config_entry.create_ticket).must_equal true
    end
    it 'adds a valid interval notification without a date' do
      @sla.add_interval_notification('Customer A', 'Database backup', 'M')

      _( @mock_notifications.size ).must_equal 1
      notification = @mock_notifications.first
      _( notification.task ).must_equal 'Database backup'
      _( notification.interval ).must_equal 'M'
      _( notification.triggered ).must_be_nil
    end

    it 'does not add a notification with an invalid interval' do
      invalid_interval = 'Z'
      out, _ = capture_io do
        @sla.add_interval_notification('Customer A', 'Invalid task', invalid_interval)
      end

      _( @mock_notifications ).must_be_empty
      _( out ).must_include "'#{invalid_interval}' is not a valid interval"
    end

    it 'does not add a notification if the customer is not found' do
      # Mock a "nil" response for a missing customer
      @config.stubs(:by_description).with('Unknown Customer').returns(nil)
      out, _ = capture_io do
        @sla.add_interval_notification('Unknown Customer', 'Task', 'W')
      end

      _( out ).must_include "customer 'Unknown Customer' not found in configuration"
    end

    it 'handles invalid date parsing and displays an error message' do
      invalid_date = 'invalid-date'
      out, _ = capture_io do
        @sla.add_interval_notification('Customer A', 'Task with bad date', 'W', invalid_date)
      end

      _( @mock_notifications ).must_be_empty
      _( out ).must_include "'#{invalid_date}' is not a valid date"
    end
  end
end
