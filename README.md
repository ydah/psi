<h1 align="center">PSI</h1>

<p align="center">
  <strong>A pure Ruby interface to Linux Pressure Stall Information</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/psi"><img src="https://img.shields.io/gem/v/psi.svg?colorB=319e8c" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/psi"><img src="https://img.shields.io/gem/dt/psi.svg" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.2-ruby.svg" alt="Ruby Version">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License">
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#triggers">Triggers</a> ·
  <a href="#supported-environments">Supported Environments</a>
</p>

---

PSI reads system-wide and cgroup v2 pressure metrics, calculates exact interval
ratios, and monitors kernel PSI triggers without a C extension.

## Features

- System-wide and cgroup v2 pressure readings for every available resource
- Exact interval ratios calculated from cumulative counters
- Kernel PSI triggers with timeout support
- Multi-trigger monitoring on a single thread
- Pure Ruby with no runtime dependencies

## Installation

```sh
bundle add psi
```

### Requirements

- Ruby 3.2+
- Linux 4.20+ with `CONFIG_PSI=y` for readings
- Linux 5.2+ and write permission on a pressure file for triggers

Distributions built with `CONFIG_PSI_DEFAULT_DISABLED=y` also require the
`psi=1` kernel command-line option.

## Usage

### Read pressure

```ruby
require "psi"

reading = PSI.read(:memory)
reading.some.avg10  # percentage over the last 10 seconds
reading.full.total  # cumulative stalled microseconds

PSI.resources # => [:cpu, :memory, :io] plus :irq where available
PSI.read_all   # => { cpu: PSI::Reading, ... }
```

`some` means at least one task was stalled. `full` means every non-idle task
was stalled. System-wide CPU pressure normally has only `some`; IRQ pressure,
available since Linux 6.1, has only `full`.

### Sample an interval

Use cumulative totals when you need an exact interval ratio instead of a
rolling average:

```ruby
sampler = PSI::Sampler.new(:memory)
sampler.sample # => nil
sleep 5
sampler.sample # => #<data PSI::Delta some_ratio=..., full_ratio=..., elapsed=...>
```

`PSI::Sampler` is intentionally not thread-safe; give each sampling thread its
own instance.

### Read the current cgroup

Containers should prefer cgroup values because `/proc/pressure` can expose the
host's system-wide pressure:

```ruby
cgroup = PSI.current_cgroup
PSI.read(:memory, cgroup: cgroup)
```

## Triggers

### Wait for a trigger

Trigger files must be writable. `/proc/pressure/*` normally requires root;
delegated cgroup v2 pressure files can be used without root. On current
kernels, an unprivileged trigger's window must be a multiple of two seconds;
privileged triggers retain the full 0.5–10 second range.

```ruby
PSI::Trigger.open(:memory, kind: :some, stall: 0.15, window: 1.0) do |trigger|
  warn "memory pressure" if trigger.wait(timeout: 10)
end
```

`window` must be 0.5–10 seconds and `stall` cannot exceed it. Start with a
`some` trigger around 10–20% of the window for early warning and a higher
`full` trigger for load shedding, then tune from measurements on the real
workload. There is no portable 10–30 second warning threshold: reclaim,
working-set size, and cgroup limits determine the lead time.

### Monitor several triggers

```ruby
monitor = PSI::Monitor.new
monitor.on_error { |error| warn error.full_message }
monitor.on(:memory, stall: 0.1, window: 1.0) { |event| warn event }
monitor.on(:io, stall: 0.3, window: 2.0) { |event| warn event }
monitor.start

# Later, during shutdown:
monitor.stop
```

Monitor uses one thread and `IO.select`'s priority set. Callback exceptions are
sent to `on_error` and do not stop monitoring. `stop` wakes the thread and
closes every trigger.

See [`examples/load_shedding.rb`](examples/load_shedding.rb) for Rack/Puma-style
503 shedding, [`examples/prometheus_exporter.rb`](examples/prometheus_exporter.rb)
for a dependency-free metrics endpoint, and
[`benchmark/monitor_idle.rb`](benchmark/monitor_idle.rb) for idle CPU
measurement.

## Supported Environments

Requiring the gem always succeeds. `PSI.supported?` reports whether the
system-wide PSI directory exists, and use on an unsupported kernel raises
`PSI::UnsupportedError`.

| Environment | Limitation |
|---|---|
| macOS and Windows | No Linux procfs PSI interface. |
| WSL2 with an old or PSI-disabled kernel | `/proc/pressure` is absent. |
| Docker Desktop and other containers | `/proc/pressure` may represent the host; trigger writes are commonly denied. Prefer a delegated cgroup. |
| GitHub-hosted runners | Readings usually work, but trigger tests require root and the host kernel cannot be changed. |
| Linux before 4.20 | PSI is unavailable. Linux before 5.2 supports readings but not triggers. |

## Development

```sh
bundle install
bundle exec rake test:unit
bundle exec rbs validate
bundle exec yard
```

Linux system tests require PSI trigger write permission:

```sh
sudo --preserve-env=PATH,GEM_HOME,GEM_PATH bundle exec rake test:system
```

## Contributing

Bug reports and pull requests are welcome at https://github.com/ydah/psi.

## License

Released under the [MIT License](LICENSE.txt).
