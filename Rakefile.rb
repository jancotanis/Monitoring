# frozen_string_literal: true

require 'dotenv/load'
require 'rake/testtask'


Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = false
end

require 'rubocop/rake_task'
RuboCop::RakeTask.new
task default: %i[rubocop]
