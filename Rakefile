# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yard"

RSpec::Core::RakeTask.new(:spec) { |task| task.pattern = "spec/*_spec.rb" }
RSpec::Core::RakeTask.new("test:system") { |task| task.pattern = "spec/system/*_spec.rb" }
YARD::Rake::YardocTask.new

namespace :test do
  task unit: :spec
  task :gc_stress do
    ruby "-Ilib", "spec/gc_stress.rb"
  end
end

task :compile
task default: "test:unit"
