# frozen_string_literal: true

module PSI
  # A pressure event delivered by Monitor.
  class Event
    attr_reader :resource, :kind, :stall, :window, :reading, :at

    def initialize(trigger:, reading:, at: Time.now)
      @resource = trigger.resource
      @kind = trigger.kind
      @stall = trigger.stall
      @window = trigger.window
      @reading = reading
      @at = at
    end

    # Formats the pressure and threshold for logs.
    # @return [String]
    def to_s
      average = reading.public_send(kind)&.avg10
      value = average ? " avg10=#{average}%" : ""
      "#{resource} #{kind}#{value} (threshold #{duration(stall)}/#{duration(window)})"
    end

    private

    def duration(seconds)
      value = seconds < 1 ? seconds * 1000 : seconds
      unit = seconds < 1 ? "ms" : "s"
      "#{value.round(3).to_s.delete_suffix(".0")}#{unit}"
    end
  end
end
