# frozen_string_literal: true

require 'test_helper'
require 'persistent_cache'

TEST_CACHE_NAME = 'test.yaml'

JOHN = { name: 'John', age: 30 }
MARC = { name: 'Marc', age: 50 }

describe '#1 cache ' do
  it '#1.1 test dynamic loader' do
    cache = PersistentCache.new(TEST_CACHE_NAME)
    # Store a new value
    cache.store(:user_1, JOHN)

    # Fetch a value from the cache or load it using a loader
    user = cache.fetch(:user_1) do
      flunk '1.1.2 Unexpected cache call'
    end
    assert _(user[:name]).must_equal 'John'

    # Fetch a value not within the cache or load it using a loader
    user = cache.fetch(:user_2) do
      MARC
    end
    assert _(user[:name]).must_equal 'Marc'

    # Fetching the same key again will return the cached value without calling the loader
    user_again = cache.fetch(:user_1)
    assert _(user_again[:name]).must_equal 'John'

    new_user = cache.fetch(:user_3)
    assert new_user.nil?, 'NO loader provided, should be nil'

    # Delete a key from the cache
    cache.delete(:user_1)
    new_user = cache.fetch(:user_1)
    assert new_user.nil?, 'Cache entry deleted NO loader provided, should be nil'
  end
  it '#1.2 test persistency' do
    persist = PersistentCache.new(TEST_CACHE_NAME)
    assert !File.exist?(TEST_CACHE_NAME), '1.2.1 empty cache, no persistent file'

    persist.store(:user_1, JOHN)
    persist.persist_cache
    assert File.exist?(TEST_CACHE_NAME), '1.2.2 empty cache, no persistent file'

    cache = PersistentCache.new(TEST_CACHE_NAME)
    # Fetch a value from the cache or load it using a loader
    user = cache.fetch(:user_1) do
      flunk '1.2.3 Unexpected cache call'
    end
    assert _(user[:name]).must_equal 'John'

    # Fetch a value not within the cache or load it using a loader
    user = cache.fetch(:user_2) do
      { name: 'Marc', age: 50 }
    end
    assert _(user[:name]).must_equal 'Marc'
    File.delete(TEST_CACHE_NAME)
  end
end
