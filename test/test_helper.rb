# frozen_string_literal: true

require 'fileutils'
require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'minitest/spec'
require 'mocha/minitest'

$LOAD_PATH.unshift File.expand_path('../', __dir__)

CACHE_FILE = 'software-index.json'
CACHE_BACKUP = 'software-index.json.bak'

Minitest.after_run do
  FileUtils.mv(CACHE_BACKUP, CACHE_FILE) if File.exist?(CACHE_BACKUP)
end

FileUtils.mv(CACHE_FILE, CACHE_BACKUP) if File.exist?(CACHE_FILE)
