# frozen_string_literal: true

require 'yaml'

# PersistentCache
#
# A simple in-memory cache that persists to a YAML file. This class provides
# caching functionality with the ability to load missing data using a "loader"
# block and persist the cache to a file for future use.
#
# == Example Usage
#   cache = PersistentCache.new('cache.yaml')
#
#   # Store a new value
#   cache.store(:user_1, { name: "John", age: 30 })
#
#   # Fetch a value from the cache or load it using a loader
#   user = cache.fetch(:user_1) do
#     { name: "John", age: 30 }  # This value would be loaded dynamically if not in cache
#   end
#
#   # Fetching the same key again will return the cached value without calling the loader
#   user_again = cache.fetch(:user_1)
#
#   # Delete a key from the cache
#   cache.delete(:user_1)
class PersistentCache
  # Initializes the cache by loading the existing cache data from a YAML file.
  #
  # @param file_path [String] the path to the YAML file where the cache will be stored
  #   Default is 'cache.yaml'.
  def initialize(file_path = 'cache.yaml')
    @file_path = file_path
    @cache = load_cache
  end

  # Fetches a value from the cache. If the key is not found, the provided loader block is used to
  # retrieve the value. The fetched value is then cached and persisted to the file.
  #
  # @param key [Symbol, String] the key for the cache entry
  # @param loader [Proc] a block that returns the value to be loaded if the key is not in the cache
  # @return [Object] the cached or loaded value
  def fetch(key, &loader)
    if @cache.key?(key)
      # Return cached value
      @cache[key]
    else
      # Use the loader if key is not found, store and persist the result
      if loader
        value = loader.call
        store(key, value)
        value
      end
    end
  end

  # Stores a value in the cache for the given key. The cache is also persisted to the file.
  #
  # @param key [Symbol, String] the key for the cache entry
  # @param value [Object] the value to be cached
  # @return [void]
  def store(key, value)
    @dirty = true
    @cache[key] = value
  end

  # Deletes a key from the cache and persists the changes to the file.
  #
  # @param key [Symbol, String] the key to be removed from the cache
  # @return [void]
  def delete(key)
    @dirty = true
    @cache.delete(key)
  end

  # Persists the current cache data to the YAML file.
  #
  # @return [void]
  def persist_cache
    # compact empty values so next time we will retry to load these
    File.write(@file_path, YAML.dump(@cache.compact)) if @dirty
  end

  private

  # Loads the cache from the YAML file, if it exists.
  # If the file doesn't exist or is empty, it returns an empty hash.
  #
  # @return [Hash] the cache data loaded from the YAML file
  def load_cache
    @dirty = false
    if File.exist?(@file_path)
      # Load YAML file or return empty hash
      YAML.load_file(@file_path) || {}
    else
      # Return empty hash if file doesn't exist
      {}
    end
  end
end
