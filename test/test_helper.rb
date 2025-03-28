# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'minitest/spec'
require 'mocha/minitest'

$LOAD_PATH.unshift File.expand_path("../", __dir__)
