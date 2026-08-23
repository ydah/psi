# frozen_string_literal: true

module PSI
  # Pressure averages and the cumulative stall time for one PSI category.
  class Metrics
    attr_reader :total

    def initialize(averages:, total:)
      @averages = averages.freeze
      @total = total
    end

    # Returns the rolling average for a window in seconds.
    # @param seconds [Integer]
    # @return [Float, nil]
    def avg(seconds)
      @averages[Integer(seconds)]
    end

    # @return [Float, nil] ten-second average
    def avg10 = avg(10)
    # @return [Float, nil] sixty-second average
    def avg60 = avg(60)
    # @return [Float, nil] three-hundred-second average
    def avg300 = avg(300)

    # Converts dynamic averages and total time to a hash.
    # @return [Hash]
    def to_h
      @averages.sort.to_h { |seconds, value| [:"avg#{seconds}", value] }.merge(total: total)
    end
  end

  # A snapshot read from one PSI resource.
  class Reading
    attr_reader :resource, :some, :full, :read_at, :metrics

    # Parses the contents of a Linux pressure file.
    # @param resource [Symbol]
    # @param text [String]
    # @param read_at [Time]
    # @return [Reading]
    def self.parse(resource, text, read_at: Time.now)
      metrics = text.each_line.filter_map do |line|
        kind, *fields = line.split
        next unless kind

        values = fields.filter_map { |field| field.split("=", 2) if field.include?("=") }.to_h
        next unless %w[some full].include?(kind) || values.key?("total")

        averages = values.filter_map do |key, value|
          [Integer(key.delete_prefix("avg")), Float(value)] if key.match?(/\Aavg\d+\z/)
        end.to_h
        [kind.to_sym, Metrics.new(averages: averages, total: Integer(values.fetch("total")))]
      end.to_h

      new(resource: resource, some: metrics[:some], full: metrics[:full], read_at: read_at, metrics: metrics)
    rescue ArgumentError, KeyError => e
      raise Error, "invalid PSI data: #{e.message}"
    end

    def initialize(resource:, some:, full:, read_at:, metrics: nil)
      @resource = resource
      @some = some
      @full = full
      @read_at = read_at
      @metrics = (metrics || { some: some, full: full }.compact).freeze
    end
  end
end
