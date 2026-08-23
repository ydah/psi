# frozen_string_literal: true

require "socket"
require "psi"

server = TCPServer.new("0.0.0.0", Integer(ENV.fetch("PORT", 9394)))
cgroup = ENV["CGROUP"]

loop do
  client = server.accept
  body = PSI.read_all(cgroup: cgroup).flat_map do |resource, reading|
    %i[some full].filter_map do |kind|
      metrics = reading.public_send(kind)
      next unless metrics

      [10, 60, 300].map { |seconds| "psi_avg{resource=\"#{resource}\",kind=\"#{kind}\",seconds=\"#{seconds}\"} #{metrics.avg(seconds)}" } +
        ["psi_total_microseconds{resource=\"#{resource}\",kind=\"#{kind}\"} #{metrics.total}"]
    end
  end.flatten.join("\n") << "\n"
  client.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
ensure
  client&.close
end
