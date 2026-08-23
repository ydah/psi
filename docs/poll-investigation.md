# PSI priority-event investigation

Tested on 2026-08-23 with Ruby 3.4.10 and Linux 6.8.0-64-generic in a
privileged Colima container.

Two CPU-pressure triggers used `some 1000 500000`. Sixteen busy child
processes generated contention. Both Ruby APIs reported the priority event:

```text
IO#wait(IO::PRIORITY, 5)          => true
IO.select(nil, nil, [io], 5)[2]   => [io]
```

The implementation therefore uses `IO#wait` for a single trigger and the
exception set of `IO.select` for `PSI::Monitor`. No C extension is needed.

Trigger registration must terminate the single write with a newline or NUL.
An unterminated write produced `EINVAL` for valid boundary values on this
kernel, while the same values with a newline registered successfully.

The check requires Linux with PSI trigger support and write permission for
`/proc/pressure/cpu`. A privileged container was required; an ordinary
container returned `EACCES`.
