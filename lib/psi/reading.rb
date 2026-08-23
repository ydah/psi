# frozen_string_literal: true

module PSI
  # Pressure averages and the cumulative stall time for one PSI category.
  class Metrics
    attr_reader :total

    def initialize(averages:, total:)
      @averages = averages.freeze
      @total = total
    end

    def avg(seconds)
      @averages[Integer(seconds)]
    end

    def avg10 = avg(10)
    def avg60 = avg(60)
    def avg300 = avg(300)

    def to_h
      @averages.sort.to_h { |seconds, value| [:"avg#{seconds}", value] }.merge(total: total)
    end
  end

  # A snapshot read from one PSI resource.
  class Reading
    attr_reader :resource, :some, :full, :read_at

    def self.parse(resource, text, read_at: Time.now)
      metrics = text.each_line.filter_map do |line|
        kind, *fields = line.split
        next unless %w[some full].include?(kind)

        values = fields.filter_map { |field| field.split("=", 2) if field.include?("=") }.to_h
        averages = values.filter_map do |key, value|
          [Integer(key.delete_prefix("avg")), Float(value)] if key.match?(/\Aavg\d+\z/)
        end.to_h
        [kind.to_sym, Metrics.new(averages: averages, total: Integer(values.fetch("total")))]
      end.to_h

      new(resource: resource, some: metrics[:some], full: metrics[:full], read_at: read_at)
    rescue ArgumentError, KeyError => e
      raise Error, "invalid PSI data: #{e.message}"
    end

    def initialize(resource:, some:, full:, read_at:)
      @resource = resource
      @some = some
      @full = full
      @read_at = read_at
    end
  end
end
