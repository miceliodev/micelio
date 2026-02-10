%{
  title: "Doubt, Conviction, and a Thank You Letter to Open Source",
  author: :pedro,
  tags: ~w(vision open-source fediverse git),
  description: "On the tension between doubting whether an alternative to Git can succeed and feeling compelled to build one anyway, as a thank you to the open source ecosystem that made everything possible."
}

---

I go back and forth on whether building Micelio makes any sense.

Not because I doubt the ideas behind it. I genuinely believe the way we version and produce software is due for a rethink. But Git is everywhere. It is the foundation our entire industry builds on. Even organizations that have outgrown it, like [Shopify](https://shopify.engineering), push Git beyond its design limits rather than consider an alternative. The gravity of that ecosystem is enormous. Convincing people to try something different feels like shouting into a storm.

And yet.

## The cracks are showing

I keep noticing signals that I am not the only one feeling this tension. People are starting to talk openly about the ways Git and the workflows built around it are struggling with the new reality of software development.

There is the conversation around **prompt requests over pull requests**, the idea that when agents are producing most of the code, reviewing diffs line by line is no longer the right interface. The unit of review should be the intent, the goal, the reasoning, not the raw text changes.

Then there is Mitchell Hashimoto's [Vouch](https://github.com/mitchellh/vouch), a trust management framework for open source projects. The premise is that AI tools have made it trivial to produce plausible-looking but low-quality contributions, so projects need a way to formalize who they trust. Vouch lets established community members vouch for newcomers, creating a web of trust where reputation flows through human relationships rather than automated checks. It is a thoughtful response to a real problem.

But I can not help thinking we need a different answer entirely. Not better tools to patch the current model, but a different model. One where the context, the reasoning, and the trust relationships are built into the version control system itself, not bolted on after the fact.

## A thank you letter

At the same time, I keep thinking about what made all of this possible in the first place.

The large language models we use every day were trained on decades of open source code and writing. Every library, every framework, every Stack Overflow answer, every blog post written by someone who just wanted to share what they learned. That collective generosity is the soil everything grows from.

I feel a responsibility to give something back. Not in a transactional way, but in the sense that building Micelio is my way of saying thank you. Thank you to every developer who published their work under a permissive license. Thank you to every maintainer who reviewed pull requests on weekends. Thank you to every person who wrote documentation because they remembered how lost they felt when they were learning.

Micelio is a thank you letter in the form of software.

## Small collectives, not monoliths

What if we could build a forge that favors small collectives instead of massive centralized platforms? What if we took inspiration from [Mastodon](https://joinmastodon.org) and the [Fediverse](https://en.wikipedia.org/wiki/Fediverse) and designed software forges as a network of independent instances that can interoperate?

A local open source community running their own instance. A university hosting one for their students. A company running one internally. All of them able to discover, follow, and collaborate across instance boundaries, the same way you can follow someone on a different Mastodon server.

This is where Micelio's architecture starts to matter. For that model to work, each instance needs to be easy to maintain. You should not need a dedicated infrastructure team to keep a forge running. That means you have to think very carefully about the pieces that traditionally make self-hosting painful.

**Storage.** Traditional Git hosting requires you to manage disk storage that grows linearly with your repositories. That is one of the main things that pushes people toward large providers. Micelio uses [S3](https://aws.amazon.com/s3/) (or any S3-compatible storage) as the source of truth, with an optional warm local disk layer for performance. S3 is cheap, practically infinite, and available from dozens of providers. A small collective does not need to worry about disk capacity planning. They just point at a bucket and go.

**CI/CD.** Continuous integration is the other piece that gets expensive fast. Build infrastructure is resource-hungry and a constant source of operational headaches. But what if we rethought the trust model? If we can trust the automation and the environment in which it runs, if we can verify not just the output but the integrity of the process, maybe we do not need every instance to run its own build farm. Maybe trust can flow through the network, and a check that ran on one instance does not need to run again on another.

**Environments.** This one is particularly interesting in an agent-first world. Agents need sandboxed environments to safely execute work remotely. Where do those environments come from? There are several possible answers, and I honestly do not know which one is right. Maybe we integrate with existing companies that already provide secure execution environments. Maybe we automate the provisioning ourselves using lower-level primitives from cloud providers. Or maybe, and this is the most exciting possibility, people can contribute sandbox capacity to the network. Imagine a model where community members donate compute the way people donate disk space to distributed storage networks. The hard question there is trust: how do you verify that a contributed environment is actually secure? How do you ensure the code running inside it has not been tampered with? I do not have answers to these questions yet, but I think they are worth exploring.

These are all open questions. I do not have all the answers yet. But I think designing for small, interoperable collectives rather than for a single dominant platform is the right direction. And every design decision in Micelio, from S3 storage to session-based workflows to environment provisioning, is shaped by the question: does this make it easier or harder for a small group to run their own instance?

## Building for the sake of giving

Some of the most important things in the world exist because someone decided they should belong to everyone.

When I walk through a public park and see kids playing, I do not think about the economics of it. I think about the fact that someone, at some point, decided this space should just exist. For anyone. With no strings attached. Public schools, public libraries, public hospitals. The best things a society builds are the ones it builds with no interest other than making life better for the people who use them.

I think software can be like that too. Especially now, when we are shaping a new approach to how software is built and shared. If we are going to rethink the tools, we should also rethink the incentives. Not everything needs a business model. Not everything needs to extract value from the people it serves.

[Mastodon](https://blog.joinmastodon.org/2024/04/mastodon-forms-new-u.s.-non-profit/) and [Ghost](https://ghost.org/about/) have shown what this looks like in practice. Both are structured as non-profits. Both have been building meaningful, sustainable software for years without venture capital, without an exit strategy, without ever having to compromise their mission for the sake of growth. They prove it is possible.

I want Micelio to follow that spirit. Not a startup. Not a company optimizing for an exit. Something closer to a public park. A place that exists because someone believed the tools we use to create software should belong to the people who use them, not to the institutions that happen to host them. If we are lucky enough to be living through a moment where software is getting cheaper to produce and infrastructure is getting easier to manage, then let us use that moment to build something generous. Something that exists for no reason other than to make the experience of building software a little more human.

## The wave

Something is shifting. You can feel it. People are frustrated with the status quo and curious about alternatives. The conversation about what comes after Git, or at least what comes alongside it, is happening whether I participate or not.

I would rather be building than watching. Even if the odds are long. Even if convincing people to try something new is as hard as I fear it might be.

Because the worst case is that I learn a lot, contribute some ideas to the conversation, and say thank you to the community that taught me everything I know.

That does not feel like a bad outcome.
