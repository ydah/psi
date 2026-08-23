# frozen_string_literal: true

require "psi"

# Rack middleware that briefly rejects requests after a memory-pressure event.
class PressureShedder
  def initialize(app)
    @app = app
    @mutex = Mutex.new
    @reject_until = 0
    @monitor = PSI::Monitor.new
    @monitor.on(:memory, stall: 0.1, window: 1.0, cgroup: ENV["CGROUP"] || PSI.current_cgroup) do |event|
      warn event
      @mutex.synchronize { @reject_until = monotonic + 10 }
    end
    @monitor.start
  end

  def call(env)
    return [503, { "content-type" => "text/plain", "retry-after" => "10" }, ["server under pressure\n"]] if rejecting?

    @app.call(env)
  end

  private

  def rejecting?
    @mutex.synchronize { monotonic < @reject_until }
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
