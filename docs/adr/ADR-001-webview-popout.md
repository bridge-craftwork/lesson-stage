# ADR-001 — The bridge popout is a webview, not a port

**Status:** Accepted
**Date:** 2026-07-22
**Supersedes:** the seed ADR in [PLAN.md](../PLAN.md)

## Context

Tapping a hand in a projected lesson PDF should open something interactive:
a deal display, card play with trick history, an auction stepper, double-dummy
analysis on demand.

Every one of those already exists. The bridge-craftwork org has a mature Vue
component gallery (board display, DD tables, auction views) and a stack of
tested Rust libraries — `bridge-types`, `bridge-encodings`, `Bridge-Parsers`,
`bridge-solver`, `bridge-rulebot`. They are gallery-tested and in daily use.

The alternative is porting those components to SwiftUI and either binding the
Rust libraries through a C FFI or reimplementing them in Swift.

## Decision

The popout hosts the existing Vue build plus the Rust libraries compiled to
`wasm32` inside a `WKWebView`. Components are not ported to SwiftUI.

The webview owns **all** bridge semantics. Native knows about PDFs, taps, and
bytes; it knows nothing about a contract, a trick, or a suit.

## Consequences

**Good.** One implementation of every bridge component, so no drift between
the web gallery and the iPad. Gallery-first testing carries over unchanged.
The Rust libraries get exactly one new build target rather than an FFI surface
per library. Fixes land in both places at once.

**Costs, accepted.** A slightly non-native feel, and a first-load cost paid on
the first popout. The interaction being served is tap-driven on a projector,
where neither matters much; the startup cost is mitigated by keeping one warm
`WKWebView` instance and reusing it across popouts.

**Constraint this imposes.** The seam is a message boundary, so everything
crossing it must be serializable: native posts `{ kind, blockBody, pbn }` in,
the webview posts close/resize requests out. Anything that would need a live
object reference across the seam is a design error on this architecture.

## Revisit if

A component needs native input that a webview handles badly — Apple Pencil
*inside* the popout is the realistic case (marking up a deal diagram during a
lesson). That would be a per-component decision, not a reversal: one native
component alongside the webview, not a wholesale port.

WASM performance is the other trigger. The double-dummy solver is the only
component with real compute behind it, and it is worth benchmarking early —
see [contract-5-consumer.md](../contract-5-consumer.md) and the Phase 0 spike
in the plan. If the solver is unusably slow in WASM, the fallback is a native
Rust build of *that library only*, called over the message bridge — which
leaves this decision intact for everything else.
