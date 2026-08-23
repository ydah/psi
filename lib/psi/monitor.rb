# frozen_string_literal: true

module PSI
  # Multiplexes PSI triggers on one background thread.
  class Monitor
    def initialize
      @entries = []
      @wake_reader, @wake_writer = IO.pipe
      @error_handler = ->(error) { warn "PSI monitor: #{error.message}" }
    end

    def on(resource, **options, &callback)
      raise ArgumentError, "a callback is required" unless callback
      raise Error, "monitor is already running" if @thread
      raise Error, "monitor is stopped" if stopped?

      @entries << [Trigger.new(resource, **options), callback]
      self
    end

    def on_error(&handler)
      raise ArgumentError, "an error handler is required" unless handler

      @error_handler = handler
      self
    end

    def start
      raise Error, "monitor is stopped" if stopped?
      return self if @thread&.alive?

      @thread = Thread.new { run }
      self
    end

    def stop
      return self if stopped?

      @stop = true
      @wake_writer.write_nonblock(".") if @thread&.alive?
      @thread.join if @thread && @thread != Thread.current
      close unless @thread
      self
    rescue Errno::EPIPE, IOError
      self
    end

    private

    def run
      triggers = @entries.to_h { |trigger, callback| [trigger.to_io, [trigger, callback]] }
      until @stop
        readable, _, priority = IO.select([@wake_reader], nil, triggers.keys)
        break if readable.include?(@wake_reader)

        priority.each { |io| notify(*triggers.fetch(io)) }
      end
    ensure
      close
    end

    def notify(trigger, callback)
      callback.call(Event.new(trigger: trigger, reading: PSI.read(trigger.resource, cgroup: trigger.cgroup)))
    rescue StandardError => e
      report_error(e)
    end

    def report_error(error)
      @error_handler.call(error)
    rescue StandardError => e
      warn "PSI monitor error handler failed: #{e.message}"
    end

    def close
      @entries.each { |trigger, _| trigger.close }
      @wake_reader.close unless @wake_reader.closed?
      @wake_writer.close unless @wake_writer.closed?
    end

    def stopped?
      @wake_reader.closed?
    end
  end
end
