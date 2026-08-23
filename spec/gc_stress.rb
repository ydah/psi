# frozen_string_literal: true

GC.stress = true

require "tmpdir"
require "psi"

100.times do
  reading = PSI::Reading.parse(:memory, "some avg10=1.0 avg60=2.0 avg300=3.0 total=4\n")
  abort "invalid reading" unless reading.some.to_h == { avg10: 1.0, avg60: 2.0, avg300: 3.0, total: 4 }
end

Dir.mktmpdir do |cgroup|
  File.write(File.join(cgroup, "memory.pressure"), "")
  100.times { PSI::Trigger.new(:memory, stall: 0.1, window: 1.0, cgroup: cgroup).close }
end
