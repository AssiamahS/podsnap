# PODsnap

Snap the signed BOL / POD, get a factoring-ready invoice packet before you leave the dock.

**Live web app:** https://assiamahs.github.io/podsnap/  
**Pricing / Start:** https://assiamahs.github.io/podsnap/pricing.html

- Camera → pages cleaned to scan-style B/W → text read **on-device** (Tesseract in the browser, Apple Vision on iPhone) → load #, BOL #, PO, shipper, consignee, rate, detention, lumper, delivery date, broker + AP email filled in.
- Factor-ready check: receiver signature, legibility, load # matches rate con, rate con attached — the usual reasons a packet bounces.
- One PDF: invoice page first, then every document page, named `Invoice-1001-Load-XXXX.pdf`. Share sheet / mail to the broker AP or the factor.
- No backend, no account, no per-scan API cost. Loads live on the device.

## Business case

| | |
|---|---|
| **Buyer** | Owner-operators and 1–5 truck carriers who invoice brokers themselves or submit to a factor (OTR Solutions, RTS, Triumph, Apex, Bobtail...). |
| **Problem** | Paperwork happens at night in the cab. Missing signatures, unreadable photos and load #s that don't match the rate con get packets kicked back; each bounce adds 24–48 hrs before funding. |
| **Price** | $14/mo Owner-operator. $29 one-time "done-with-you" setup (includes first 60 days). Free in-browser trial. |
| **Competitors** | Rigbooks ~$19/mo, TruckingOffice $20–30/mo (full TMS, heavier), LoadPal (Microdea) ~$60/mo, HaulStat $39–59/truck/mo, factor-owned apps (free but locked to that factor). PODsnap is the cheapest thing that does just this one job, works with any factor, and nothing leaves the phone. |

### Evidence

- Factors say a missing receiver signature is the #1 POD rejection, then illegible scans and mismatched reference numbers; each rejection adds 24–48 hrs — https://otrucking.com/resources/guides/pod-for-factoring/
- Mistakes that slow invoice funding (missing/unsigned docs, mismatched details) — https://www.saintjohncapital.com/common-factoring-mistakes-youre-making-that-slow-invoice-funding/
- Rigbooks $19/mo, TruckingOffice $20+/mo — https://softwareconnect.com/trucking/rigbooks , https://fitsmallbusiness.com/truckingoffice-review
- LoadPal invoicing app (camera doc scan + invoice tracking for owner-operators, $60/mo) — https://www.overdriveonline.com/new-loadpal-invoicing-app/
- HaulStat $39 / $59 per truck/mo, factoring exports on Pro — https://haulstat-marketing.pages.dev/
- Solo devs shipping niche paid tools with Claude Code (e.g. $12/mo Mac app → reported $20K MRR; "distribution is what kills indie projects") — https://aicheatcode.substack.com/p/he-built-a-20k-mrr-mac-app-with-claude , https://youcanbuildthings.substack.com/p/how-to-make-money-with-claude-code
- Owner-operators already use generic tools (QuickBooks) for invoicing — https://www.thetruckersreport.com/truckingindustryforum/posts/4614336/

### First dollar (24 h)

1. Set `PAY_URL` (Stripe Payment Link for $14/mo, or a $29 one-time link) and `CONTACT` in `web/config.js`, push.
2. Post the free web app (not a pitch) in r/OwnerOperators, r/Truckers, r/FreightBrokers (the "your paperwork bounces" angle), TruckersReport forum "Owner Operators" board, and the Facebook groups *Owner Operator Truckers*, *Hot Shot Trucking*, *Box Truck Owners*, *Power Only Carriers*. Box truck / hotshot newcomers get bounced most.
3. DM 20 carriers who posted "factoring" or "paperwork" questions in the last week. Offer the $29 setup — you load their logo, NOA remit-to and factor email, and check their first 3 packets.
4. Ask factoring sales reps (they get paid on funded volume) if they'll hand PODsnap to new carriers; cleaner packets = faster funding for them too.

## Setting the payment link

Edit `web/config.js`:

```js
window.PODSNAP_CONFIG = {
  PAY_URL: "https://buy.stripe.com/xxxxxxxx",   // any checkout link
  CONTACT: "you@example.com",                    // or "+15551234567" for SMS
  PRICE_MONTHLY: 14,
  PRICE_PILOT: 29
};
```

Empty `PAY_URL` → the Start button opens a request-access form that composes an email (or SMS if `CONTACT` is a phone number). Push to `main`; the `pages` workflow redeploys.

## Layout

```
web/      static PWA, no build step (index.html app, pricing.html sales page, config.js)
ios/      XcodeGen project (iOS 26.0+, com.assiamah.podsnap), SwiftUI + SwiftData + Vision + VisionKit
tests/    node tests/extract.test.mjs — field extractor on sample BOL / rate con text
.github/  pages.yml (deploy web/), ios.yml (Xcode 27 runner, unsigned simulator build)
```

### iPhone Duo

Built on the Xcode 27 runner (iOS 27.x SDK) so it fills the 7.6" inner display. `NavigationSplitView` gives loads | detail; the detail splits again into paperwork | invoice when the width is regular and ≥ 600 pt. Folded, it collapses to a stack with a two-step segmented flow. The selected load, the step, the column visibility (`@SceneStorage`) and every field (SwiftData) survive a fold.

Signing/TestFlight are not in CI yet (Apple account billing hold) — the workflow proves it compiles against the Duo SDK.
