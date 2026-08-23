# frozen_string_literal: true

require "io/wait"

module PSI
  # A kernel PSI trigger tied to an open pressure file descriptor.
  class Trigger
    KINDS = %i[some full].freeze
    MIN_WINDOW_US = 500_000
    MAX_WINDOW_US = 10_000_000

    attr_reader :resource, :kind, :stall, :window, :cgroup

    def self.open(...)
      trigger = new(...)
      return trigger unless block_given?

      begin
        yield trigger
      ensure
        trigger.close
      end
    end

    def initialize(resource, kind: :some, stall:, window:, cgroup: nil)
      @resource = resource.respond_to?(:to_sym) ? resource.to_sym : resource
      @kind = kind.respond_to?(:to_sym) ? kind.to_sym : kind
      @stall = Float(stall)
      @window = Float(window)
      @cgroup = cgroup
      validate!
      register
    end

    def wait(timeout: nil)
      raise Error, "trigger is closed" if closed?

      !!@io.wait(IO::PRIORITY, timeout)
    end

    def close
      @io&.close unless closed?
      nil
    end

    def closed?
      !@io || @io.closed?
    end

    def to_io
      raise Error, "trigger is closed" if closed?

      @io
    end

    private

    def validate!
      raise ArgumentError, "kind must be :some or :full" unless KINDS.include?(kind)
      raise ArgumentError, "stall must be greater than zero" unless stall.positive? && stall.finite?
      raise ArgumentError, "window must be between 0.5 and 10.0 seconds" unless window.finite? && window_us.between?(MIN_WINDOW_US, MAX_WINDOW_US)
      raise ArgumentError, "stall must not exceed window" if stall_us > window_us
      raise ArgumentError, "cpu has no full pressure metric" if resource == :cpu && kind == :full && !cgroup

      PSI.path_for(resource, cgroup: cgroup)
      warn "PSI: cpu full pressure may be unavailable for this cgroup" if resource == :cpu && kind == :full
    end

    def register
      @io = File.open(PSI.path_for(resource, cgroup: cgroup), File::RDWR)
      @io.sync = true
      @io.write("#{kind} #{stall_us} #{window_us}")
    rescue Errno::ENOENT => e
      discard_io
      raise UnsupportedError, e.message
    rescue Errno::EINVAL, Errno::EBUSY, Errno::ENOMEM, Errno::EOPNOTSUPP, Errno::EACCES => e
      discard_io
      raise TriggerError, "cannot register #{resource} #{kind} trigger (#{e.class.name}): #{e.message}"
    rescue StandardError
      discard_io
      raise
    end

    def stall_us = (stall * 1_000_000).round
    def window_us = (window * 1_000_000).round

    def discard_io
      @io&.close
      @io = nil
    end
  end
end
