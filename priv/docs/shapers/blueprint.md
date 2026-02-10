%{
  title: "Blueprint",
  description: "Ideas, hypotheses, and completed solutions guiding Micelio."
}
---

## Backlog

### Attested work without traditional CI

Can we use cryptography and controlled environments to attest that work was done and verified, so we do not need a separate continuous integration check? A plausible path is to treat the session tree hash and its surrounding metadata as the unit of attestation, signed by the environment that executed the work. If the environment also records toolchain versions, runtime configuration, and test outputs, then policy can shift from rerunning CI to verifying that an attestation exists, is trustworthy, and matches the landed tree. The remaining work is defining the minimum signing scope and handling nondeterministic tests without eroding the value of the attestation.

### Maintainers execute prompt requests

Can maintainers be the ones in charge of executing prompt requests, either in remote environments or locally? This model would make maintainers the trusted execution gatekeepers, with contributors submitting prompts and maintainers producing the resulting session artifacts. Open source development might move toward reviewing prompt intent and session outputs rather than accepting direct code from unknown machines. The tradeoff is throughput versus confidence, and the system must make audit trails and execution context explicit so the community can see how and where a change was produced.

### LLMs, libraries, and Micelio design

If LLMs can produce code, do we still need libraries, and what would that mean for open source and the design of Micelio? Libraries remain the encoded memory of shared behavior, security assumptions, and stable interfaces that keep systems coherent, even when code is generated on demand. If generation becomes more common, libraries may evolve toward reference implementations and compatibility contracts rather than hand-built utilities. For Micelio, this pushes the design toward capturing dependency sets and tool versions as part of the session environment so generated code remains reproducible and reviewable.
