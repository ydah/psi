# frozen_string_literal: true

module PSI
  # Stall ratios calculated from two consecutive readings.
  Delta = Data.define(:some_ratio, :full_ratio, :elapsed)

  # Calculates exact stall ratios from cumulative PSI totals.
  class Sampler
    def initialize(resource, cgroup: nil)
      @resource = resource
      @cgroup = cgroup
    end

    # Takes a sample and returns a delta after the first call.
    # @return [Delta, nil]
    def sample
      reading = PSI.read(@resource, cgroup: @cgroup)
      sampled_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return remember(reading, sampled_at) unless @previous

      elapsed = sampled_at - @sampled_at
      previous = @previous
      remember(reading, sampled_at)
      Delta.new(
        some_ratio: ratio(reading.some, previous.some, elapsed),
        full_ratio: ratio(reading.full, previous.full, elapsed),
        elapsed: elapsed
      )
    end

    private

    def remember(reading, sampled_at)
      @previous = reading
      @sampled_at = sampled_at
      nil
    end

    def ratio(current, previous, elapsed)
      return unless current && previous

      [current.total - previous.total, 0].max / (elapsed * 1_000_000)
    end
  end
end
