# frozen_string_literal: true
require 'rake/testtask'
Rake::TestTask.new(:test) do |task|
  task.libs << 'test'
  task.pattern = 'test/*_test.rb'
end
Rake::TestTask.new('test:db') do |task|
  task.libs << 'test'
  task.pattern = 'test/integration/*_test.rb'
end
task default: :test
