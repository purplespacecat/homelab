# Decision record: FluxCD over ArgoCD

**Decided:** January 2026, when GitOps was introduced (the original 522-line
feature comparison this file used to hold is in git history if you want it).

## The choice

FluxCD manages this cluster. ArgoCD was the alternative considered.

## Why Flux won

- **Memory.** Flux's controllers run in roughly 150–200MB; ArgoCD wants
  500MB+. On a single 8GB node that also runs the entire monitoring stack
  and Jellyfin, that difference is real capacity.
- **Enforcement fits a solo maintainer.** Flux is pull-only with no manual
  sync button. With nobody else to catch "I'll just kubectl this one thing",
  the tool refusing drift is a feature, not friction.
- **CLI-first matches how this cluster is operated** — over SSH and in
  scripts, not through a browser.
- **Work relevance.** Learning the tool used professionally was part of the
  point of this homelab.

## What was given up

- ArgoCD's web UI: visual diffs, sync status, and app topology are genuinely
  better for learning and debugging. The trade here is `flux get` + Grafana's
  Flux dashboard (`infrastructure/monitoring/flux-dashboard.yaml`).
- Multi-source Applications (chart from upstream + values from Git in one
  resource). Flux's answer — inline values in the HelmRelease — turned out
  to be the convention this repo prefers anyway.

## When to revisit

If the cluster grows real multi-app complexity, or if someone else starts
operating it and needs the UI, re-evaluate. For a single node with one
maintainer, the decision has held since January without regret.
