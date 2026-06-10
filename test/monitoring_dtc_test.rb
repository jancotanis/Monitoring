# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../MonitoringDTC'

class MonitoringDTCTest < Minitest::Test
  FakeItem = Struct.new(:title)

  def setup
    @monitor = MonitoringDTC.new({})
  end

  def test_high_priority_with_kritiek
    item = FakeItem.new('Kritiek lek in software')
    assert @monitor.high_priority?(item)
  end

  def test_high_priority_with_ernstig
    item = FakeItem.new('Ernstig beveiligingsprobleem')
    assert @monitor.high_priority?(item)
  end

  def test_high_priority_with_actief_misbruik
    item = FakeItem.new('Actief misbruik gedetecteerd')
    assert @monitor.high_priority?(item)
  end

  def test_high_priority_case_insensitive
    item = FakeItem.new('kritiek probleem')
    assert @monitor.high_priority?(item)
  end

  def test_not_high_priority
    item = FakeItem.new('Informatieve update zonder impact')
    refute @monitor.high_priority?(item)
  end
end
