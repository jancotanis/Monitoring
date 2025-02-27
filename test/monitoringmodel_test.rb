# frozen_string_literal: true

require 'test_helper'

require 'MonitoringModel'

SOURCE = 'MiniTest'
class TestIncident < MonitoringIncident
  def initialize(device = nil, start_time = nil, end_time = nil, alert = nil)
    super(SOURCE, device, start_time, end_time, alert)
  end
end
Alert = Struct.new(:id, :description, :severity, :type, :endpoint_id, :created)
TEST_ALERT = Alert.new(1, 'Test alert', 'high')
TEST_ENDPOINT = MonitoringEndpoint.new(1, 'test-type', 'test.io', 'test-tenant', 'ok')

MockTenant = Struct.new(:id, :description)
class MockIgnore
  attr_accessor :count

  def initialize
    @count = 0
  end

  def method_missing(*)
    @count += 1
    nil
  end
end

class MockClient
attr_reader :tenants

  def initialize(tenants=[])
    i = 0
    @tenants = tenants.map { |s| MockTenant.new( i += 1, s )}
  end
end

describe '#1 MonitoringIncident' do
  it '#1.1 test timestring' do
    time = Time.new
    i = MonitoringIncident.new(SOURCE, nil, time, time, nil)
    assert _(i.time_to_s).must_equal time.to_s, '1.1 simple moment in time'

    time = Time.new - (24 * 60 * 60)
    time_2 = Time.new

    i = MonitoringIncident.new(SOURCE, nil, time, time_2, nil)
    assert _(i.time_to_s).must_equal "#{time} - #{time_2}", '1.2 time interval'
  end
  it '#1.2 test id' do
    time = Time.new
    i = MonitoringIncident.new(SOURCE, nil, time, time, TEST_ALERT)
    assert _(i.incident_id).must_equal "#{SOURCE}-1", '1.2 incident id from source+alert'
  end
  it '#1.3 test to_s' do
    time = Time.new
    i = MonitoringIncident.new(SOURCE, nil, time, time, TEST_ALERT)
    assert i.to_s[TEST_ALERT.severity] , '1.3.1 check severity in to_s'
    assert i.to_s[TEST_ALERT.description] , '1.3.1 check description in to_s'
  end
end
describe '#2 MonitoringEndpoint' do
  it '#2.1 test initialization' do
    ep = TEST_ENDPOINT

    assert _(ep.alerts).must_equal [], '2.1.1 default alert empty array'
  end
  it '#2.2 test clear alerts' do
    ep = MonitoringEndpoint.new(1, 'test-type', 'test.io', 'test-tenant', 'ok', nil, [1,2,3])

    assert ep.alerts.count > 0, '2.2.1 default alert empty array'

    ep.clear_alerts
    assert _(ep.alerts).must_equal [], '2.2.2 default alert empty array'
  end
end
describe '#3 CustomerAlerts' do
  it '#3.1 test initialization' do
    ca = CustomerAlerts.new('Company')
    assert _(ca.alerts).must_equal [], '3.1.1 cs alerts'
    assert _(ca.devices.count).must_equal 0, '3.1.1 cs devices'
  end
  it '#3.2 add incident' do
    time = Time.new
    ca = CustomerAlerts.new('Company')
    ep = TEST_ENDPOINT
    alert = Alert.new(1, 'Test alert', 'High', 'Test-type', ep.id, Time.new)
    ca.add_incident(ep.id, alert, TestIncident)
    ## .alerts seems not in use
    ##assert _(ca.alerts.count).must_equal 0, '3.2.1 cs new alert'
    assert _(ca.devices.count).must_equal 1, '3.2.2 cs new devices'
    assert _(ca.devices[ep.id].count).must_equal 1, '3.2.3 cs incident added to device'
    assert _(ca.devices[ep.id][alert.type].start_time).must_equal alert.created, '3.2.3 cs incident times equal'

    # check endtime change for new alert
    alert2 = Alert.new(2, 'Test alert', 'High', 'Test-type', ep.id, time + 24*60*60)
    ca.add_incident(ep.id, alert2, TestIncident)
    assert _(ca.devices[ep.id].count).must_equal 1, '3.2.4 cs incident added to device'
    assert _(ca.devices[ep.id][alert.type].start_time).must_equal alert.created, '3.2.3 cs incident times equal'
    assert _(ca.devices[ep.id][alert.type].end_time).must_equal alert2.created, '3.2.3 cs incident end tiem updated'

    # check new alert type
    alert3 = Alert.new(3, 'Test alert', 'High', 'Test-type2', ep.id, time)
    ca.add_incident(ep.id, alert3, TestIncident)
    assert _(ca.devices[ep.id].count).must_equal 2, '3.2.5 cs incident added to device'
  end
  it '#3.3 remove reported incidents' do
    ca = CustomerAlerts.new('Company')
    ep = TEST_ENDPOINT
    alert = Alert.new(1, 'Test alert', 'High', 'Test-type', ep.id, Time.new)
    ca.add_incident(ep.id, alert, TestIncident)
    alert2 = Alert.new(2, 'Test alert', 'High', 'Test-type2', ep.id, Time.new)
    ca.add_incident(ep.id, alert2, TestIncident)

    ca.remove_reported_incidents([])
    assert _(ca.devices[ep.id].count).must_equal 2, '3.3.1 no incidents removed'

    ca.remove_reported_incidents([alert.id])
    assert _(ca.devices[ep.id].count).must_equal 1, '3.3.2 one incidents removed'

    ca.remove_reported_incidents([alert2.id])
    assert _(ca.devices.count).must_equal 0, '3.3.3 one device removed'
  end
  it '#3.4 report' do
    ca = CustomerAlerts.new('Company')
    ep = TEST_ENDPOINT
    alert = Alert.new(1, 'Test alert', 'High', 'Test-type', ep.id, Time.new)
    assert ca.report.nil?, '3.4.0 empty report'
    
    ca.add_incident(ep.id, alert, TestIncident)
    s = ca.report
    assert s[ca.name], '3.4.1 customer name'
    assert s["(#{ep.id})"], '3.4.2 device id'
    assert s[alert.description], '3.4.3 customer name'
    assert s[alert.severity], '3.4.4 customer name'
  end
end
describe '#4 AbstractMonitor' do
  it '#4.1 initializes' do
    client = MockClient.new
    config = MockIgnore.new
    report = nil
    log = nil
    am = AbstractMonitor.new(SOURCE, client, report, config, log)
    assert _(config.count).must_equal 1, '4.1 load called'
  end
  it '#4.2 run' do
    client = MockClient.new(['Company 1', 'Company 2'])
    config = MockIgnore.new
    report = nil
    log = nil
    am = AbstractMonitor.new(SOURCE, client, report, config, log)
    assert_raises(NotImplementedError) do
      am.run([])
    end
  end
end