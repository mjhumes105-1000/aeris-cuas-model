# AERIS-Nexus data-link (comms) architecture — recommended baseline

**Status: provisional recommendation pending expert review.** All numbers are
engineering estimates, not a frozen spec. The data link is **separate from the
X-band sensing radar** (see the in-band note at the end).

## The decision, up front

| element | baseline | why |
|---|---|---|
| **Message protocol** | Cursor-on-Target (CoT) events | DoD standard for position/track; natively consumed by ATAK/WinTAK — the operator's "loaded map" |
| **Transport / network** | TAK mesh over a COTS tactical MANET radio; self-healing mesh routing (OLSR/BATMAN-class), IP/UDP | self-forming, self-healing = attrition tolerance, which is the architecture's whole point |
| **RF band** | **900 MHz ISM (902–928 MHz)** primary; L-band a licensed alternative | best range + NLOS/foliage penetration per watt; low bands win because our data rate is low |
| **Tx power** | 1 W (30 dBm), COTS-typical | ~2–5 km omni range (link budget below) without exotic hardware |
| **Antennas** | omni whip (3 dBi) for mesh relay; optional directional (~12 dBi) for near-pair → C2 backhaul | omni so any node relays any direction; directional only where a long fixed hop needs it |
| **Receiver** | integrated SDR MANET transceiver, NF ~6 dB, sensitivity ~−108 dBm | COTS; sensitivity sets the range |
| **Data rate** | ~100 kbps provisioned (needs far less) | track/plot fusion is tiny; see below |
| **Security** | AES-256 link encryption (standard on tactical MANET) | — |

## Why the data rate is the hinge

Everything above follows from **how much data crosses the link**, and that is set
by the **fusion level** we chose (track/plot fusion, not raw-IQ fusion):

- A track/plot report — id, position, velocity, covariance, time, class,
  confidence — is on the order of **~100 bytes**. A handful of tracks at a few
  Hz is **a few kbps**. Provision 100 kbps and you have 20× headroom.
- Raw range-Doppler or IQ fusion would need **tens of Mbps per node** and force
  a high-bandwidth (short-range, higher-frequency) link. We do **not** do that —
  each node runs its own detector/tracker and shares the low-rate result. That
  choice is what makes a cheap, long-range, sub-GHz mesh viable.

So: **low fusion data rate → sub-GHz is affordable → range and NLOS are good →
the mesh holds together under attrition.** The comms choice and the fusion
architecture are the same decision.

## Link budget (grounds `commsRange`, not a magic number)

`aeris.comms_range` computes achievable range from the RF parameters using
Friis with a terrestrial log-distance path-loss exponent (free-space n=2 is
wildly optimistic near the ground; 2.7–3.5 is realistic):

```
sensitivity   = -174 + 10log10(rate) + NF + Eb/N0req
max path loss = Ptx + Gtx + Grx - sensitivity - fade margin
```

At 1 W, omni 3 dBi both ends, 100 kbps, NF 6 dB, Eb/N0 10 dB, 12 dB margin
(sensitivity ≈ **−108 dBm**):

| band | benign (n=2.7) | moderate (n=3.0) | foliage (n=3.5) |
|---|---|---|---|
| **900 MHz** | 5.2 km | **2.2 km** | 0.7 km |
| L-band 1.4 GHz | 3.8 km | 1.7 km | 0.6 km |
| 2.4 GHz | 2.5 km | 1.2 km | 0.4 km |
| 5.8 GHz | 1.3 km | 0.6 km | 0.3 km |

- **900 MHz beats the higher bands by 2–4×** in range, for the same power — the
  case for going low when you don't need bandwidth.
- A **directional backhaul** (12 dBi both ends) at 900 MHz reaches **~9 km**, so
  a far-out pair can reach C2 on one fixed hop.
- Multi-hop mesh multiplies coverage: the far pair relays through the near pair,
  so end-to-end reach is the sum, at the cost of one hop of latency each.

This is why the paired defense-in-depth layout works: with ~2 km node spacing
and a 2–5 km link, every node is either in direct range of C2 or one hop from a
node that is.

## Frequency deconfliction with the radar

The sensing radar is X-band (**9.5 GHz**); the data link is **900 MHz** — nearly
a decade apart, so there is no self-interference and no filtering headache. This
is the main reason to keep comms **out-of-band** rather than on the radar.

## Antennas and receivers, concretely

- **Mesh/relay:** a vertical omni (dipole/whip), ~3 dBi, mounted on the same
  mast as the radar but electrically independent. Any node can hear any
  neighbour, which is what the self-healing mesh needs.
- **Backhaul (optional):** a small Yagi/panel (~12 dBi) aimed near-pair → C2
  where a long fixed hop is wanted; buys the ~9 km reach above.
- **Receiver:** the MANET radio is an integrated SDR transceiver (Tx+Rx in one
  box); NF ~6 dB and ~−108 dBm sensitivity are COTS-typical and set the range.
- Comms antennas are **physically separate** from the X-band radar aperture.

## COTS options (illustrative, not an endorsement)

- **Tactical MANET (higher cost, best resilience):** Silvus StreamCaster,
  TrellisWare TSM, Persistent Systems Wave Relay — MIMO self-healing mesh,
  AES, sub-6 GHz tunable. The "right" answer if budget allows.
- **Low-cost attritable:** 900 MHz mesh modules (Doodle Labs Mesh Rider,
  Meshtastic/LoRa-class for pure telemetry). LoRa is dirt-cheap and very long
  range but low rate + high latency — acceptable only for track reports, not
  plots. Fits the "attritable" cost target best.

The tension between "tactical-grade resilient" and "cheap enough to lose" is a
real architecture trade and belongs in the study. Track-level fusion keeps the
door open to the cheap end.

## The in-band option (joint radar–comms) — considered, not recommended

It is technically possible to carry data **on the X-band radar aperture** itself
(dual-function radar-communications / JCR). We do **not** baseline it because:

- It **steals sensing duty cycle** — every symbol spent communicating is a dwell
  not spent detecting, directly eroding the warning the node exists to provide.
- It is **complex and immature** for a low-cost attritable node — the opposite
  of the architecture philosophy.
- It couples two subsystems that are cleaner kept independent (a jammed or
  killed comms path should not degrade sensing, and vice-versa).

A separate 900 MHz mesh is cheaper, simpler, more resilient, and out of the
radar's way. Revisit in-band only if antenna/SWaP constraints ever forbid a
second aperture.

## What is modelled vs. specified

`aeris.comms` + `aeris.comms_range` model **connectivity and latency** —
reachability to C2, relay hops, per-hop delay into the warning chain, and
graceful degradation under link loss / node kills. They do **not** model the CoT
message format, the TAK software stack, or waveform-level PHY; those are
specification, captured here.
