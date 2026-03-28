%{
  title: "Rethinking the Foundations",
  author: :pedro,
  tags: ~w(vision git infrastructure agents),
  description: "AI is exposing cracks in our industry's foundations. Git, forges, CI pipelines. It might be time to rethink all of it."
}

---

Something is breaking. Not in a dramatic, everything-is-on-fire way, but in the slow, structural way that only becomes obvious once you stop and look at where the pressure is building. AI is making code production faster. A lot faster. What used to take a team days now takes an agent minutes. The volume of code flowing through our systems has changed by an order of magnitude, and the infrastructure we built to handle it was never designed for this. We are starting to see the cracks.

## The bottlenecks are showing

The most visible one is code review. When agents can produce pull requests at a pace that no human team can keep up with, review becomes the bottleneck. There are companies jumping into that space, building tools to help humans review faster or to have agents review other agents' work. That part of the problem is getting attention. But there is a bigger elephant in the room, and I think it is [Git](https://git-scm.com/) itself.

[GitHub](https://github.com/) has been running into stability issues more frequently than ever. I believe this is not a coincidence. They were not expecting this volume of code being produced, and they are building on a technology that was not designed for it either. The result is the instability we have been seeing. And some of the optimizations happening around it feel like patches on a deeper problem. Warm cache clones for CI environments, for example. You are optimizing the wrong layer.

## This is not new

Large companies figured this out years ago. [Google](https://google.com/), [Meta](https://about.meta.com/), and others eventually moved away from Git into monorepos with custom build systems that model all dependencies explicitly. This lets them be selective about what they pull, what they build, and what they test. They did not arrive there because they wanted to be different. They arrived there because Git stopped scaling for them. What I find interesting is that this kind of selectivity, the ability to work with just the slice of code you need, should span the entire stack. From the build toolchain all the way down to version control. It should not be an afterthought bolted on top. It should be foundational. This is why I think it is a good time to rethink the foundations of our industry.

## Falling in love with the problem

I am a person that falls in love with problems. Technologies have always been a means to an end for me. I happen to fall in love with random domains, and this is one that has been building an appetite in me for a while now. It is what led me to start building an alternative to both Git as a technology and the forge as a platform. When I set out to build the foundation for Micelio, I looked at what was out there and what principles I wanted to follow. Two things became very clear early on.

## The cost problem

These days it is cheap to produce code and cheap to host it. But there are elements where things get very expensive. Running a git forge requires a big company behind it. You need to think about infrastructure, about how to distribute repositories horizontally, about uptime and scale. Technologies like object storage exist and could make a real difference here. [Turbopuffer](https://turbopuffer.com/) is a good example of creative use of [S3](https://aws.amazon.com/s3/). But the barrier to running your own forge remains high, and that limits innovation. Then there is continuous integration. Having someone run those machines, maintaining the infrastructure, depending on their availability. It is another costly layer that sits between you and shipping code.

One of the things I want to explore with Micelio is this: how can we design something so cheap and simple to host that it encourages a different model? A model where organizations run their own forge internally. Maybe there is still a default one that people go to, like [GitHub](https://github.com/) today, but the system incentivizes self-hosting because the requirements are so minimal that you just decide to do it. This is why I have been exploring a system where object storage plays a central role in storing repositories. [S3](https://aws.amazon.com/s3/) gives you durability, availability, and the economics are hard to beat. If the forge is mostly a thin layer on top of object storage, the barrier to running one drops dramatically.

## Beyond portability

[Git](https://git-scm.com/) makes your repositories portable. You can work offline, commit offline. That is genuinely great. But when the repository becomes very large and you have to push and pull, it is an all-or-nothing approach in terms of breadth. You can control the depth with shallow clones, but the breadth of code you work with is not something you can easily control. I have been thinking about a system where the build toolchain and your environment can virtually see the entire repository, all the files, all the history, but you only pull what you actually need. You warm your local cache with just the files relevant to your current task, fetched from cheap storage. Some companies are already doing this internally. [Google](https://google.com/) is one of them. The question is: can we design an open alternative with the best ideas from Git, where this selective access is the core model upon which everything builds?

## Sessions, not commits

Then there is the question of primitives. Git's building blocks were designed for a different era. Today, so much decision-making happens during an agentic session. The conversation, the reasoning, the context behind why certain decisions were made. All of that gets lost. Even sessions that do not end up producing code that lands on main are gone, and I think that is a missed opportunity. This is valuable context and knowledge that should live next to the history of changes.

I am trying to rethink the primitives from scratch. Throw away branches, commits, merging, rebasing, and all those concepts. Start from what we actually need today. What are the things we need to capture from how we work with agents, both at the version control level and at the forge level? Do pull requests still make sense? Do issues? How are people actually working today? Maybe it is less about creating an issue in a tracker and more about capturing an idea from anywhere, spawning a session from anywhere, including your local environment, and then proposing something that could land on the trunk of the repository. The unit of work is not a commit. It is a session with a goal, a conversation, decisions, and changes.

## Making CI obsolete

There is another piece that does not need to live inside version control itself but should be part of the ecosystem. Think about what [Shopify](https://shopify.engineering/) is doing building their own build system on top of [Nix](https://nixos.org/). In these deterministic environments, you know exactly what is inside. If there is a system that uses cryptographic hashes to verify builds and test results, we could reach a point where we do not need CI as we know it today. Instead of trusting some random pipeline that ran somewhere, in some environment, and then produced a green checkmark, you trust the system itself. If a check says the code has been compiled and tested, and the environment is deterministic and verifiable, you can trust that result. The focus shifts from trusting pipelines to trusting the code. This is especially relevant when agents have already done the compute work locally in a known environment.

I do not know if [Bazel](https://bazel.build/) or [Nix](https://nixos.org/) will be the thing that fills this role, but there are interesting ideas in that space. And if you design it to integrate deeply with the forge, you could make the entire concept of CI obsolete.

## Building in the open

There is an opportunity to build all of this. A version control system designed for how we actually work today. A forge so cheap to run that self-hosting becomes the natural choice. Primitives that capture not just what changed but why. And a build model that makes CI unnecessary. I do not have all the answers yet. But I have the problem, and I am in love with it. I will share more as these pieces come together.
