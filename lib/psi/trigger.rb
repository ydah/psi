# frozen_string_literal: true

require "io/wait"

module PSI
  # A kernel PSI trigger tied to an open pressure file descriptor.
  class Trigger
    # Triggerable pressure categories.
    KINDS = %i[some full].freeze

    attr_reader :resource, :kind, :stall, :window, :cgroup

    # Opens a trigger and closes it after the optional block.
    # @return [Trigger, Object] the trigger, or the block result
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

    # Closes the descriptor and unregisters the kernel trigger.
    # @return [nil]
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
      raise ArgumentError, "stall must be greater than zero" unless stall.finite? && stall_us.positive?
      raise ArgumentError, "window must be between 0.5 and 10.0 seconds" unless window.finite? && window.between?(0.5, 10.0)
      raise ArgumentError, "stall must not exceed window" if stall > window
      raise ArgumentError, "cpu has no full pressure metric" if resource == :cpu && kind == :full && !cgroup

      PSI.path_for(resource, cgroup: cgroup)
      warn "PSI: cpu full pressure may be unavailable for this cgroup" if resource == :cpu && kind == :full
    end

    def register
      @io = File.open(PSI.path_for(resource, cgroup: cgroup), File::RDWR)
      @io.sync = true
      @io.write("#{kind} #{stall_us} #{window_us}\n")
    rescue Errno::ENOENT => e
      discard_io
      raise UnsupportedError, e.message
    rescue Errno::EINVAL, Errno::EBUSY, Errno::ENOMEM, Errno::EOPNOTSUPP, Errno::EACCES, Errno::EPERM => e
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
