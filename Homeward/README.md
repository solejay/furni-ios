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

### Design

Plain words, premium surfaces. The interface speaks the customer's language (you pay, they receive, fee, exchange
rate, on its way, delivered) and takes its visual polish from current fintech patterns and Meng To's public design
playbook:

- **Home**: your balance over a dot-matrix map built from Natural Earth land data, with a line from your city to each
  place you send to. A transfer that's on its way shows as a card with a progress track.
- **Amount screen**: a large amount with its own tactile keypad (after Cash App's pattern). Type what you send or what
  they get; "Show the maths" opens the full breakdown with comparison bars.
- **Review**: the transfer receipt before you send it, the rate-lock countdown, and **slide to send**, which is
  deliberate friction before money moves (a single action for VoiceOver). Then a clear "Sent" confirmation.
- **Transfer receipt**: how much arrives, who receives it, what you paid, the fee, the rate, the reference, and the
  bank payout reference once delivered. A progress list runs from created to delivered.
- **Activity**: transfers grouped by month with plain status labels: Delivered, On its way, Processing, Delayed,
  Cancelled, Refunded.
- **One accent only**: navy glass everywhere, with marigold reserved for actions and transfers in progress. Green and
  red are semantic only.
- **Apple Liquid Glass, used where Apple intends it**: only on the navigation and control layer, never on content.
  - The system `TabView` adopts Liquid Glass, minimizes on scroll (`.tabBarMinimizeBehavior(.onScrollDown)`) and
    carries a bottom accessory, like Music's mini player. It shows the transfer that's on its way, with live
    progress, or a quick "Send money".
  - Controls use real glass:
    - keypad keys: interactive glass inside a `GlassEffectContainer`
    - the You send / They get selection: glass that morphs across with `glassEffectID`
    - currency chips: clear glass over the map
    - the slide-to-send knob: tinted, interactive glass
    - `.glassProminent` for the one primary action per screen, and a glass rate-alert banner
  - Content (balance card, receipts, the rate dial, lists) sits on solid surfaces (`contentSurface()`). There is no
    glass on glass, and only primary actions are tinted.
  - `LiquidGlass.swift` wraps `glassEffect`, `GlassEffectContainer`, `glassEffectID` and the glass button styles behind
    `#available(iOS 26.0, *)`, with a material fallback for iOS 17–25.
- **Flat colour**: solid fills only, with no gradients, glows or light effects. Dark objects (the balance card and
  receipt heads) use one solid navy (`Theme.night`). A transfer on its way gets a plain marigold edge
  (`.beam(active:)`).
- **Rate weather** as a calibration dial: one tick per earlier day, lit when today's rate beats it (`RateDial`).
- **Background**: one flat colour, deep navy at night and warm paper by day (`AtmosphereBackground`). Mono
  micro-labels and 01/02/03 step markers on the send flow.
- **People**: each person shows as their real photo once you add one (Photos picker on their page, or on Account for
  you), otherwise as a plain solid colour. Photos are kept as small JPEGs on the device, outside the ledger.
- **Type**: the prototype pairs Newsreader (feeling) with Geist (numbers) and Geist Mono (labels). The app uses the
  system serif, sans and monospaced faces in the same roles.

### Made for how families actually send

- **Family Pot**: siblings in London, Houston and Toronto each chip in from their own currency toward one payout home,
  a digital *ajo* for looking after parents. A live ring shows everyone's share. Contributions are fee-free, the pot
  shows the separate-transfer fees it avoided, and the recipient gets one payment instead of several.
- **Rate Weather**: today's rate as weather ("☀️ Sunny day to send: today's rate beats 26 of the last 29 days"). It
  describes the past 30 days and never pretends to forecast.
- **Delivery postcards**: every delivered transfer can become a postcard for WhatsApp. Its pattern is generated just for
  that transfer and inspired by the recipient's textile traditions: Yoruba *adire* indigo for Nigeria, *kente* strips
  for Ghana, Maasai beadwork for Kenya and *bandhani* dots for India.
- **Your Year Home**: a story-style recap of twelve months: total sent, who you supported most, how much more reached
  your family than through a typical bank, your most generous month and your fastest delivery.

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
    │   ├── Delight.swift        Rate Weather, Family Pots, Your Year Home
    │   └── Ledger.swift         The customer's whole state, plus send/cancel rules and demo data
    └── Tests/HomewardCoreTests  46 unit tests
```

All pricing, validation and transfer rules live in `HomewardCore`, so they are unit-tested and can be shared with a
backend or another client. The SwiftUI layer only presents them.

## Running

1. Open `Homeward/Homeward.xcodeproj` in **Xcode 26** or later. The Liquid Glass APIs only exist in the iOS 26 SDK;
   the deployment target stays iOS 17, and older systems get a material fallback.
2. Choose the **Homeward** scheme and an iOS 17+ simulator, then run. On a device, choose your team under Signing.

The app starts with demo data. **Account → Reset demo data** restores it.

Things to try:
- **Send money → £200 to Nigeria**: watch the breakdown, then open the comparison card.
- **Type the receive amount instead**: the send amount is worked out for you, cheapest first.
- **New recipient → GTBank → `2201456785`**: the check digit is wrong, and the app says so before any lookup.
  `2201456784` is valid.
- **Any account number containing `999`**: the bank lookup returns a different owner, which shows the mismatch warning.
- **Pay from balance, then cancel** before delivery: the money goes straight back to the balance.
- **Home → Mum's 70th birthday**: add your share to the family pot and watch the ring fill, then send it home.
- **Open a delivered transfer → Send a postcard**: each one has its own generated pattern.
- **Home → Your year home**: tap through the recap.
- **Rate alerts**: add an "at or above" alert at today's rate. Sample rates swing about ±0.25% over a cycle of roughly
  five minutes, so the banner fires within a few minutes. Targets further out may never be reached in the demo.

## Web prototype

`Prototype/index.html` is a self-contained, clickable version of the app (plain HTML and JavaScript). Open it in any
browser. It ports the core's pricing, validation, pot, weather and recap rules, and keeps demo state in the browser.

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
