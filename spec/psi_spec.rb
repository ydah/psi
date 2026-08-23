# frozen_string_literal: true

RSpec.describe PSI do
  around do |example|
    Dir.mktmpdir do |root|
      described_class.procfs_root = root
      example.run
    ensure
      described_class.procfs_root = nil
    end
  end

  it "detects support and available resources" do
    expect(described_class).not_to be_supported
    FileUtils.mkdir_p(File.join(described_class.procfs_root, "pressure"))
    FileUtils.touch(File.join(described_class.procfs_root, "pressure/memory"))

    expect(described_class).to be_supported
    expect(described_class.resources).to eq([:memory])
  end

  it "reads resources and cgroups" do
    pressure = File.join(described_class.procfs_root, "pressure")
    FileUtils.mkdir_p(pressure)
    File.write(File.join(pressure, "memory"), "some avg10=1.0 total=2\n")

    expect(described_class.read(:memory).some.total).to eq(2)

    cgroup = File.join(described_class.procfs_root, "cgroup")
    FileUtils.mkdir_p(cgroup)
    File.write(File.join(cgroup, "io.pressure"), "full avg10=3.0 total=4\n")
    expect(described_class.read(:io, cgroup: cgroup).full.avg10).to eq(3.0)
  end

  it "reads every available resource" do
    pressure = File.join(described_class.procfs_root, "pressure")
    FileUtils.mkdir_p(pressure)
    %w[cpu io].each { |name| File.write(File.join(pressure, name), "some avg10=0 total=0\n") }

    expect(described_class.read_all.keys).to eq(%i[cpu io])
  end

  it "resolves the current cgroup v2 path" do
    FileUtils.mkdir_p(File.join(described_class.procfs_root, "self"))
    File.write(File.join(described_class.procfs_root, "self/cgroup"), "0::/user.slice/example\n")

    expect(described_class.current_cgroup).to eq("/sys/fs/cgroup/user.slice/example")
  end

  it "rejects unknown resources" do
    expect { described_class.read(:network) }.to raise_error(ArgumentError, /unknown resource/)
  end
end
