# frozen_string_literal: true

require "psi"

duration = Float(ENV.fetch("DURATION", 5))
monitor = PSI::Monitor.new.on(:memory, stall: 1.0, window: 10.0, cgroup: ENV["CGROUP"]) {}
cpu_started = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
wall_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
monitor.start
sleep duration
monitor.stop
cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu_started
wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_started
puts "idle CPU: #{(cpu / wall * 100).round(3)}% (#{wall.round(3)}s)"
