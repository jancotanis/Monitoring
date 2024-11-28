# frozen_string_literal: true

require 'json'

# Monkeypatch for the Struct class to enhance JSON serialization and property access.
class Struct
  # Converts the Struct instance to a JSON representation.
  #
  # This method overrides the default behavior, ensuring that the struct's hash representation is converted to JSON.
  #
  # @param _options [Hash] (optional) Options for JSON generation. Ignored in this implementation.
  # @return [String] A JSON string representing the struct.
  #
  # @example
  #   MyStruct = Struct.new(:name, :age)
  #   s = MyStruct.new("John", 30)
  #   s.to_json # => "{\"name\":\"John\",\"age\":30}"
  def to_json(_options = {})
    to_h.to_json
  end

  # Retrieves a nested value from a JSON-like structure using dot-separated keys.
  #
  # This method assumes that the struct contains a `raw_data` method or attribute that holds a nested
  # hash or JSON object. It traverses the `raw_data` using the provided dot-separated property path.
  #
  # @param name [String] A dot-separated string representing the property path (e.g., "a.b.c").
  # @return [String] The value found at the specified path, or an empty string if the path doesn't exist
  # or `raw_data` is not defined.
  #
  # @example
  #   MyStruct = Struct.new(:raw_data)
  #   s = MyStruct.new({ "a" => { "b" => { "c" => "value" } } })
  #   s.property("a.b.c") # => "value"
  #   s.property("a.b.d") # => ""
  def property(name)
    if raw_data
      item = raw_data
      name.split('.').each do |o|
        item = item[o] if item&.is_a?(Hash) || item&.is_a?(WrAPI::Request::Entity)
      end
      item.to_s
    else
      ''
    end
  end
end

# Utility class for file operations with timestamping.
class FileUtil
  # Writes content to a specified file.
  #
  # This method creates or overwrites a file with the given name and writes the provided content to it.
  #
  # @param file_name [String] The name of the file to be written.
  # @param content [String] The content to write to the file.
  #
  # @example
  #   FileUtil.write_file("example.txt", "Hello, World!")
  def self.write_file(file_name, content)
    File.open(file_name, 'w') do |f|
      f.puts(content)
    end
  end

  # Generates a timestamp string in the format 'YYYY-MM-DD'.
  #
  # @return [String] The current date as a string.
  #
  # @example
  #   FileUtil.timestamp # => "2024-11-07"
  def self.timestamp
    Time.now.strftime('%Y-%m-%d').to_s
  end

  # Appends a timestamp to a file name, preserving the file extension.
  #
  # The method modifies the file name by adding a timestamp before the file extension.
  #
  # @param file_name [String] The original file name.
  # @return [String] The file name with the timestamp appended.
  #
  # @example
  #   FileUtil.daily_file_name("report.txt") # => "report-2024-11-07.txt"
  def self.daily_file_name(file_name)
    ext = File.extname(file_name)
    file_name.gsub(ext, "-#{timestamp}#{ext}")
  end

  # Generates a daily log file name based on the class name of an object.
  #
  # The method derives the log file name from the object's class name, converts it to lowercase,
  # and appends a timestamp.
  #
  # @param object [Object] The object whose class name is used to generate the log file name.
  # @return [String] The daily log file name.
  #
  # @example
  #   module MyModule; end
  #   FileUtil.daily_module_name(MyModule) # => "my_module-2024-11-07.log"
  def self.daily_module_name(object)
    daily_file_name(object.class.name.split('::').first.downcase + '.log')
  end
end

# A utility class for defining enumerations as constants.
#
# The `Enum` class provides a simple way to create constant values
# from an array of symbols or strings. Optionally, it applies a transformation
# to each value using a specified method or a `Proc`.
class Enum
  # Dynamically defines constants from an array of values.
  #
  # Each value in the array is transformed using the provided method or `Proc`
  # and set as a constant with the uppercase version of the value's name.
  #
  # @param array [Array<Symbol, String>] An array of values to be defined as constants.
  # @param proc [Symbol, Proc] The method or `Proc` to transform each value. Default is `:to_s`.
  #
  # @example Using default `:to_s` transformation
  #   Enum.enum([:apple, :banana])
  #   Enum::APPLE  # => "apple"
  #   Enum::BANANA # => "banana"
  #
  # @example Using a custom method (`:upcase`)
  #   Enum.enum([:apple, :banana], :upcase)
  #   Enum::APPLE  # => "APPLE"
  #   Enum::BANANA # => "BANANA"
  #
  # @example Using a custom Proc
  #   Enum.enum([:apple, :banana], ->(s) { s.to_s.reverse })
  #   Enum::APPLE  # => "elppa"
  #   Enum::BANANA # => "ananab"
  def self.enum(array, proc = :to_s)
    array.each do |c|
      const_set c.upcase, c.send(proc)
    end
  end
end
