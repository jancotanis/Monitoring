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

class MockClient
  attr_accessor :tenants

  def initialize
    @tenants = []
  end

  def alerts(_tenant_id)
    [MockAlert.new('CPU Overload', '123', Time.now)]
  end
end

class MockTenant
  include MonitoringTenant

  attr_accessor :name, :endpoints, :alerts

  def initialize(name)
    @name = name
    @endpoints = {}
    @alerts = []
  end
end

class MockAlert
  include MonitoringAlert

  attr_accessor :description

  def initialize(description)
    @description = description
  end
end

class MockAlert
  include MonitoringAlert

  attr_accessor :description, :endpoint_id, :created

  def initialize(description, endpoint_id, created)
    @description = description
    @endpoint_id = endpoint_id
    @created = created
  end

  def create_endpoint
    MonitoringEndpoint.new(endpoint_id, 'Server', 'server1.example.com', 'Tenant1', 'active', nil, [])
  end
end

class MockConfig
  def initialize
    @configs = {}
  end

  def load_config(_source, _tenants); end

  def by_description(description)
    @configs[description]
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
    assert i.to_s[TEST_ALERT.severity], '1.3.1 check severity in to_s'
    assert i.to_s[TEST_ALERT.description], '1.3.2 check description in to_s'
  end
end
describe '#2 MonitoringEndpoint' do
  it '#2.1 test initialization' do
    ep = TEST_ENDPOINT

    assert _(ep.alerts).must_equal [], '2.1.1 default alert empty array'
  end
  it '#2.2 test clear alerts' do
    ep = MonitoringEndpoint.new(1, 'test-type', 'test.io', 'test-tenant', 'ok', nil, [1, 2, 3])

    assert ep.alerts.any?, '2.2.1 default alert empty array'

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

    assert _(ca.devices.count).must_equal 1, '3.2.2 cs new devices'
    assert _(ca.devices[ep.id].count).must_equal 1, '3.2.3 cs incident added to device'
    assert _(ca.devices[ep.id][alert.type].start_time).must_equal alert.created, '3.2.3 cs incident times equal'

    # check endtime change for new alert
    alert2 = Alert.new(2, 'Test alert', 'High', 'Test-type', ep.id, time + (24 * 60 * 60))
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
describe AbstractMonitor do
  let(:client) { MockClient.new }
  let(:report) { {} }
  let(:config) { MockConfig.new }
  let(:log) { Minitest::Mock.new }
  let(:monitor) { AbstractMonitor.new('SourceName', client, report, config, log) }
  let(:tenant) { MockTenant.new('Tenant1') }
  let(:alert) { MockAlert.new('High CPU Usage', '456', Time.now) }

  describe '#initialize' do
    it 'initializes the monitor with the correct source' do
      _(monitor.source).must_equal 'SourceName'
    end
  end

  describe '#run' do
    it 'runs the monitor, processes customer alerts, and persists the alerts' do
      tenant = MockTenant.new('Tenant1')
      client.tenants = [tenant]
      monitor.stub(:collect_data, nil) do
        monitor.stub(:process_customer_alerts, nil) do
          monitor.stub(:persist_alerts, nil) do
            result = monitor.run({})
            _(result).must_equal({})
          end
        end
      end
    end
  end

  describe '#process_active_tenants' do
    it 'yields tenants that meet the monitoring criteria' do
      tenant = MockTenant.new('Tenant1')
      client.tenants = [tenant]
      config.stub(:by_description, nil) do
        monitor.stub(:monitor_tenant?, true) do
          yielded_tenants = []
          monitor.send(:process_active_tenants) { |t, _| yielded_tenants << t }
          _(yielded_tenants).must_equal [tenant]
        end
      end
    end
  end
  describe '#create_endpoint_from_alert' do
    it 'creates and returns an endpoint from the given alert' do
      endpoint_id = alert.endpoint_id

      # Ensure the endpoint doesn't exist in the customer's endpoints initially
      _(tenant.endpoints[endpoint_id]).must_be_nil

      # Call the method to create an endpoint from the alert
      endpoint = monitor.create_endpoint_from_alert(tenant, alert)

      # Check that the endpoint is created and added to tenant's endpoints
      _(endpoint).must_be_instance_of MonitoringEndpoint
      _(endpoint.id).must_equal endpoint_id
      _(tenant.endpoints[endpoint_id]).must_equal endpoint
      _(endpoint.hostname).must_equal 'server1.example.com'
      _(endpoint.type).must_equal 'Server'
    end

    it 'returns the existing endpoint if already present in tenant' do
      existing_endpoint = MonitoringEndpoint.new(alert.endpoint_id, 'Server',
                                                 'existing.example.com', 'Tenant1', 'active', nil, [])
      tenant.endpoints[alert.endpoint_id] = existing_endpoint

      result_endpoint = monitor.create_endpoint_from_alert(tenant, alert)

      # Check that the existing endpoint is returned
      _(result_endpoint).must_equal existing_endpoint
    end
  end
end

describe MonitoringTenant do
  let(:tenant) { MockTenant.new('Tenant1') }
  let(:endpoint1) { MonitoringEndpoint.new(1, 'Server', 'server1.example.com', 'Tenant1', 'active', nil, []) }
  let(:endpoint2) { MonitoringEndpoint.new(2, 'Database', 'db1.example.com', 'Tenant1', 'active', nil, []) }

  before do
    tenant.endpoints = { endpoint1.id => endpoint1, endpoint2.id => endpoint2 }
  end

  describe '#clear_endpoint_alerts' do
    it 'clears alerts for all endpoints' do
      endpoint1.alerts << 'Disk Space Alert'
      endpoint2.alerts << 'CPU Usage Alert'

      tenant.clear_endpoint_alerts

      _(endpoint1.alerts).must_be_empty
      _(endpoint2.alerts).must_be_empty
    end
  end

  describe '#description' do
    it 'returns the tenant name as the description' do
      _(tenant.description).must_equal 'Tenant1'
    end
  end
end

describe MonitoringAlert do
  let(:alert) { MockAlert.new('High CPU Usage', '123', Time.new) }

  describe '#type' do
    it 'returns the description as the alert type' do
      _(alert.type).must_equal 'High CPU Usage'
    end
  end
end
