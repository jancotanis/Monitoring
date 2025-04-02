# frozen_string_literal: true

require 'test_helper'
require 'utils'

TestStruct = Struct.new(:raw_data)
class Testnum < Enum
  enum %w[A B C]
end

describe '#2 utils' do
  it '#2.1.1 FileUtils' do
    assert value(FileUtil.daily_file_name('error.log')).must_equal("error-#{FileUtil.timestamp}.log"),
           '2.1.1 daily name'
  end
  it '#2.1.2 FileUtils' do
    assert value(FileUtil.daily_module_name('')).must_equal("string-#{FileUtil.timestamp}.log"),
           '2.1.2 daily module name'
  end
  it '#2.2 Struct' do
    string = '{"id":"id-0", "desc":{"someKey":"someValue","anotherKey":"value"},'\
             '"main_item":{"stats":{"a":8,"b":12,"c":10}}}'
    t = TestStruct.new(JSON.parse(string))
    assert value(t.property('key')).must_equal '', '2.2.1 property not exist'
    assert value(t.property('id')).must_equal 'id-0', '2.2.1 property '
    assert value(t.property('desc.someKey')).must_equal 'someValue', '2.2.1 nested property'
    assert value(t.property('main_item.stats.a')).must_equal '8', '2.2.1 nested property'
  end
  it '#2.3 Struct.json' do
    MyStruct = Struct.new(:name, :age)
    struct = MyStruct.new('John', 30)
    assert _(struct.to_json).must_equal '{"name":"John","age":30}', '2.3 json test'
  end
  it '#2.4 Enums' do
    assert _(Testnum::A).must_equal 'A', '2.4 constants A'
    assert _(Testnum::B).must_equal 'B', '2.4 constants B'
    assert _(Testnum::C).must_equal 'C', '2.4 constants C'
    assert _(Testnum.constants.size).must_equal 3, '2.4 3 constants defined'
    assert_raises(NameError) do
      Testnum::D
    end
  end
end
