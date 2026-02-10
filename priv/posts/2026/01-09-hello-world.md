%{
  title: "Micelio: Growing Software Like Nature Grows Forests",
  author: :pedro,
  tags: ~w(vision exploration agents),
  description: "Why I named this project after fungal networks, and what it means to build version control that thinks like a living system."
}

---

Beneath every forest floor lies an invisible network. [Mycelium](https://en.wikipedia.org/wiki/Mycorrhizal_network), the root structure of fungi, connects trees across vast distances, sharing nutrients, water, and chemical signals. A dying tree sends its carbon to its neighbors. A seedling in the shade receives sugars from a giant that can reach the sun. The forest thinks together.

I keep coming back to this image as I build Micelio.

Software development is entering a similar moment of connection. AI agents are no longer assistants waiting for instructions. They are collaborators making thousands of decisions, reasoning through problems, building alongside us. The question is not whether this will happen. It is already happening at [OpenAI](https://openai.com), [Google](https://deepmind.google), and [Meta](https://ai.meta.com), where agents and humans work together at scales [Git](https://git-scm.com) was never designed for.

The question is: what kind of network do we want to grow?

## The Hidden Intelligence of Forests

In a healthy forest, mycelium does something remarkable. It does not just transport resources. It carries information. When a pest attacks one tree, chemical signals travel through the fungal network to warn its neighbors. The forest learns. It adapts. It remembers patterns across generations.

Git, for all its brilliance, captures only the surface. It records what changed: these lines were added, those were removed, this file was created. But it discards the reasoning. Why did we choose [JWT](https://jwt.io) over sessions? What security constraints shaped the authentication design? Which approaches did we consider and reject? That context, the actual intelligence of the work, vanishes the moment a commit is finalized.

Imagine if the forest only recorded which trees existed, but forgot everything about how they communicated, what signals they exchanged, what wisdom they passed along. That is what we are doing with our software today.

## Growing Something New

This is where mic and Micelio come in.

**mic** is a new version control protocol designed from the ground up for a world where humans and agents collaborate as peers. Instead of commits, mic has sessions: complete units of work that capture not just what happened, but why it happened and how decisions were made. A session is like a conversation, a record of reasoning that future collaborators (human or AI) can learn from.

**Micelio** is the forge that makes mic accessible. It is to mic what [GitHub](https://github.com) is to git, but built for different assumptions. Where GitHub optimizes for human review of code changes, Micelio optimizes for understanding decision-making. Where GitHub scales through complexity, Micelio scales through simplicity: object storage for unlimited capacity, stateless compute to avoid bottlenecks, session-based interfaces that work at enterprise scale.

The name matters to me. Micelio is Spanish for mycelium. I wanted something that evokes networks of intelligence, shared context, and organic growth. Software is not a machine we assemble. It is a living system we cultivate.

## Letting Go of Old Mental Models

Building this has required me to step outside comfortable defaults. I have carried certain mental models about "good engineering" for a long time. They served me well. But Micelio is an experiment in seeing what becomes possible when I stop mapping new tools onto old workflows.

The most common instinct when a powerful new tool appears is to ask: "Where does this fit in my existing process?" That is reasonable. It is also a trap. If the tool changes the cost of iteration, it changes what is rational to build. If it changes how reasoning can be captured and replayed, it changes what we should value.

So I am allowing the workflow to change first, then letting the architecture follow. I am not trying to preserve the old shape of work. I am trying to preserve what matters: clarity, leverage, and momentum.

## Agents at the Center

Micelio is not a product with an AI assistant bolted on. Agents are core. They write code. They write documentation. They write blog posts. I am not hiding that behind a marketing layer, because the point is to learn in public what an agent-first workflow feels like when you stop treating agents as a sidekick.

My job becomes different. I spend less time executing and more time guiding: defining constraints, choosing tools and feedback mechanisms, setting a direction that makes it easier for an agent to do the right thing. When that guidance is good, the work compounds. When it is vague, the output drifts.

This is why I am paying more attention to system boundaries, naming, and ergonomics than I used to. These are not "just code style" anymore. They are the interface between intent and execution. They are the chemical signals traveling through the network.

## The Loop as the Unit of Progress

In an agent-first world, the unit of progress is the iteration loop. I push, monitor, and iterate in very short cycles. I care less about whether a given patch is perfect on the first try, and more about whether the loop is fast enough that imperfection is cheap.

This is where checks matter. Not just tests in the narrow sense, but the full set of things that establish confidence: compilation, formatting, static analysis, runtime assertions, and anything else we treat as required. If checks are slow, they become a tax. If checks are fast and easy to run locally, they become part of the thinking process.

The result is a different rhythm. Work becomes a stream of small hypotheses, each validated by checks and by running code, rather than a sequence of large, carefully staged changes that rely on delayed verification.

I still switch into the slower, more reflective mode of engineering. After a burst of fast iteration, I revisit the code wearing the "senior engineer" hat: remove accidental complexity, fix awkward seams, reduce coupling, make the system easier to reason about. Agents optimize for the objective you give them. If the objective is "ship the feature," you will get shipped features, along with the rough edges that accumulate when nobody is tasked with smoothing them down. Future-proofing is not a vibe. It is a set of deliberate edits.

Fast loops get you to something real. Senior loops keep it clean enough that future agents can move quickly without tripping over yesterday's choices.

## Choosing Technologies That Reveal Themselves

I am being more opinionated about the stack than I usually am. I want short feedback cycles and mental models that are easy for agents to reason about. That points me toward technologies that are explicit, inspectable, and friendly to runtime exploration.

[Elixir](https://elixir-lang.org) and [Phoenix](https://www.phoenixframework.org) fit that goal well. The runtime is alive, observable, and built around message passing and clear boundaries. [LiveView](https://hexdocs.pm/phoenix_live_view) keeps the feedback loop tight for UI work without requiring a lot of moving parts. When an agent can ask the running system what it is doing, you get better iteration than when everything is hidden behind build steps and opaque tooling.

This is a theme I expect to keep reinforcing: pick systems that make state visible, errors understandable, and change inexpensive. If the goal is to collaborate with agents at high tempo, you do not want a stack that forces long pauses between idea and evidence.

## The Path Forward

This is very much work in progress. I am not ready for production use yet, but the vision feels clear, and I am building it piece by piece.

Near term: session interfaces, conflict resolution, performance optimization.
Medium term: agent SDKs, migration tools, ecosystem growth.
Long term: a standard for agent-first development.

Both mic and Micelio are fully [open source](https://github.com/pepicrft/micelio). The forge and the CLI are developed in the open, and anyone can contribute or self-host.

## Tending the Network

Back to the forest. What makes mycelium powerful is not any single connection, but the pattern of connection. Individual trees come and go. The network persists, carrying accumulated wisdom forward.

I think about this when I consider what we are building with software. The code we write today will be modified, extended, refactored, and eventually replaced. What persists? The reasoning. The context. The why behind the what.

If we can capture that reasoning, if we can make it part of the version history rather than something that lives only in our heads or scattered Slack threads, then we are building something that gets smarter over time. Not just bigger. Smarter.

That is the bet. Micelio is my attempt to grow software the way nature grows forests: as a living network of shared intelligence, where humans and agents collaborate as peers, where context flows freely, and where the accumulated wisdom of every decision becomes soil for the next generation of work.

Git was revolutionary for its time. I think it is time for what comes next.

**Micelio is my bet on that future.**
