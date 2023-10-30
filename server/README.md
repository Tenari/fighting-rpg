# Overview

To support MMO-type performance, it needs to be written in a fast language, (like C or Rust), and it needs to be written with concurrency in mind (like Rust). We'll need to persist state in some non-intrusive way (don't want to hit disk on every player input, but also don't want to let disk representations diverge from in-memory representations **too** much). And it needs to be scalable in a relatively fluid way to support a changing userbase size.

The main pieces are:

- simulation (game engine takes in player input and current state, in order to mutate the state)
- persistence (sql database)
- communication (UDP protocol for performance, custom payload format for efficiency)
- p2p matchmaking, and match validation (for when two players try to fight each other)


