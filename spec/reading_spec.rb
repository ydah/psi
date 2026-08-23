# frozen_string_literal: true

RSpec.describe PSI::Reading do
  it "parses known lines, dynamic averages, unknown keys, and a large total" do
    reading = described_class.parse(:memory, <<~TEXT)
      some avg10=1.25 avg60=2.5 avg300=3.75 avg600=4.5 future=ignored total=18446744073709551615
      unknown avg10=99 total=99
      full avg10=0.0 avg60=0.1 avg300=0.2 total=42
    TEXT

    expect(reading.resource).to eq(:memory)
    expect(reading.some.avg10).to eq(1.25)
    expect(reading.some.avg(600)).to eq(4.5)
    expect(reading.some.total).to eq(18_446_744_073_709_551_615)
    expect(reading.full.to_h).to eq(avg10: 0.0, avg60: 0.1, avg300: 0.2, total: 42)
  end

  it "handles a missing full line and final newline" do
    reading = described_class.parse(:cpu, "some avg10=0 avg60=0 avg300=0 total=1")

    expect(reading.some.total).to eq(1)
    expect(reading.full).to be_nil
  end

  it "rejects malformed known lines" do
    expect { described_class.parse(:memory, "some avg10=nope\n") }.to raise_error(PSI::Error, /invalid PSI data/)
  end
end
