# Homeward

A money-transfer app for sending money home (UK, EU, US and Canada → Nigeria, Ghana, Kenya and India), built in SwiftUI.
It's designed around the things people most often complain about in remittance apps: hidden FX markup, money stuck in
"processing" with no explanation, transfers sent to the wrong account, surprise limits and slow support.

> Demo build: rates are sample data, transfers are simulated and no real money moves.

## What makes it better

| Common pain | What Homeward does |
| --- | --- |
| "The rate looked good but the recipient got less" | Every quote shows the **mid-market rate, our margin (0.4%), the fee and the total cost**, plus an illustrative comparison with a typical bank and app. Fees are waived above £250 / €300 / $300 / CA$400. |
| Rate changes between quoting and paying | The rate is **locked for 30 minutes** at review, with a visible countdown. If it expires, you get a fresh quote and nothing is sent at the old one. |
| Money sent to the wrong account | **Offline checks as you type**: Nigerian NUBAN check digits (catches every single-digit typo), Ghana MoMo network prefixes, M-Pesa, IFSC and UPI formats. Then a **name check**: we ask the receiving bank who owns the account and compare it with the name you typed (handles surname-first order, accents, nicknames). A mismatch needs explicit confirmation. |
| "Processing" for hours with no information | A **live tracker** with each step timestamped, an ETA, an honest "taking longer than usual" banner when it's late, and a payout reference on delivery that the recipient's bank can trace. |
| Hard to cancel or get refunds | **Cancel free until payout**. Money already paid is refunded automatically, with no support ticket. |
| Surprise limits mid-transfer | Daily and monthly **limits shown up front** in Account, and checked on the amount screen before you continue. |
| Support asks for details you already gave | **Help is attached to the transfer**, with the reference and status already filled in. |
| Watching rates manually | **Rate alerts** with a 30-day chart and "x% better than the 30-day average". |
| Sending the same amount every month | **Recurring transfers** ("Mum's monthly allowance") that you can pause, delete or send early. |

Also included: a multi-currency balance with top-up, recipients with verified-name badges and delivery totals, searchable activity grouped by month, shareable receipts, local notifications, haptics, Dynamic Type-friendly layouts and VoiceOver labels.

## Project layout

```
Homeward/
├── Homeward.xcodeproj           Xcode 16+ project (folder-synced groups)
├── Homeward/                    SwiftUI app (iOS 17+)
│   ├── HomewardApp.swift        App entry, tabs, rate-alert banner
│   ├── AppStore.swift           Observable store: persistence, live rates, simulator, notifications
│   └── Views/                   Home, Send flow, Tracker, Activity, Recipients, Account, Alerts
└── HomewardCore/                Platform-neutral Swift package with all the money logic
    ├── Sources/HomewardCore
    │   ├── Money.swift          Currency, Money (Decimal, minor-unit rounding), formatting
    │   ├── Rates.swift          Rate provider, sample rates, deterministic rate history
    │   ├── Quote.swift          Pricing policy, quote engine (send/receive), comparisons
    │   ├── Recipient.swift      Countries, payout rails, banks, recipients
    │   ├── Validation.swift     NUBAN/MoMo/M-Pesa/IFSC/UPI validation, name matching
    │   ├── Transfer.swift       Transfer state machine, tracking steps, delivery estimates
    │   ├── Alerts.swift         Rate alerts, recurring schedules, verification tiers and limits
    │   ├── Wallet.swift         Multi-currency wallet, demo transfer simulator
    │   └── Ledger.swift         The customer's whole state, plus send/cancel rules and demo data
    └── Tests/HomewardCoreTests  37 unit tests
```

All pricing, validation and transfer rules live in `HomewardCore`, so they are unit-tested and can be shared with a
backend or another client. The SwiftUI layer only presents them.

## Running

1. Open `Homeward/Homeward.xcodeproj` in Xcode 16 or later.
2. Choose the **Homeward** scheme and an iOS 17+ simulator, then run. On a device, choose your team under Signing.

The app starts with demo data. **Account → Reset demo data** restores it.

Things to try:
- **Send money → £200 to Nigeria**: watch the breakdown, then open the comparison card.
- **Type the receive amount instead**: the send amount is worked out for you, cheapest first.
- **New recipient → GTBank → `0123456786`**: the check digit is wrong, and the app says so before any lookup.
  `0123456785` is valid.
- **Any account number containing `999`**: the bank lookup returns a different owner, which shows the mismatch warning.
- **Pay from balance, then cancel** before delivery: the money goes straight back to the balance.
- **Rate alerts**: add an "at or above" alert at today's rate. Sample rates swing about ±0.25% over a cycle of roughly
  five minutes, so the banner fires within a few minutes. Targets further out may never be reached in the demo.

## Tests

```sh
cd Homeward/HomewardCore
swift test
```

`HomewardCore` has no Apple-only dependencies, so the tests also run on Linux (for example in the `swift:6.1` Docker image).

## Production notes

The demo stands in for real services in a few places. The seams are:
- **Rates**: `RateProvider` (swap `USDCrossRates.sample()` for a live feed).
- **Account name lookup**: `AccountNameResolver` (NIBSS name enquiry, MoMo or M-Pesa KYC lookups, and so on). The app
  uses `AppStore.lookUpAccountName` as a demo stand-in.
- **Transfer progress**: `TransferSimulator` stands in for webhooks or push updates from the payout partner.
- **Comparisons**: `ProviderBenchmark.illustrative` uses stated assumptions, not data about named providers.
