# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../Monitoring'

describe Monitoring::CLI do
  let(:cli) { Monitoring::CLI.new }

  def parse(args)
    options = {}
    cli.send(:build_option_parser, nil, nil, options).parse!(args)
    options
  end

  it 'lists monitor names without Monitor suffix' do
    _(Monitoring::CLI.monitor_names).must_include 'sophos'
    _(Monitoring::CLI.monitor_names).must_include 'integra365'
  end

  it 'runs all monitors by default' do
    cli.instance_variable_set(:@options, parse([]))
    _(cli.send(:selected_monitor_classes)).must_equal Monitoring::CLI::MONITOR_CLASSES
  end

  it 'runs a single monitor' do
    cli.instance_variable_set(:@options, parse(%w[-m Sophos]))
    _(cli.send(:selected_monitor_classes)).must_equal [SophosMonitor]
  end

  it 'runs multiple monitors' do
    cli.instance_variable_set(:@options, parse(%w[--monitor veeam,zabbix]))
    _(cli.send(:selected_monitor_classes)).must_equal [VeeamMonitor, ZabbixMonitor]
  end

  it 'rejects unknown monitors' do
    _ { parse(%w[-m foo]) }.must_raise OptionParser::InvalidArgument
  end

  it 'skips compact when monitors are selected' do
    config = mock
    config.expects(:compact!).never
    cli.instance_variable_set(:@config, config)
    cli.instance_variable_set(:@options, { monitors: ['sophos'], compact: true })
    cli.send(:compact_config)
  end

  it 'compacts when all monitors are run' do
    config = mock
    config.expects(:compact!).once
    cli.instance_variable_set(:@config, config)
    cli.instance_variable_set(:@options, { compact: true })
    cli.send(:compact_config)
  end
end
