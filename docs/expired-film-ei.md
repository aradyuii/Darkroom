# Expired film: the exposure index model

`Expand → Tools → Expired film EI`.

Film past its printed date has usually lost speed and gained base fog. The
calculator answers one question — what exposure index should this roll be shot
at? — and refuses to answer any other. It recommends no developer, no dilution
and no time, and it never suggests that correct exposure repairs a film that has
chemically degraded.

The whole engine is plain Swift with no SwiftUI in it:

| File | What it holds |
| --- | --- |
| `Expiry/ExpiryModel.swift` | Vocabulary: storage tiers and timelines, evidence classes, behaviour groups, distributions, the H&D curve, the EI ladder, requests and results |
| `Expiry/ExpiryParameters.swift` | The eight group priors, the catalogue rules that place every library film, era adjustment, bundled per-film overrides |
| `Expiry/ExpiryEngine.swift` | Sampling, thermal and radiation ageing, curve inversion, assembly, confidence, wording |
| `Expiry/ExpiryCalibration.swift` | Roll observations, hierarchical shrinkage, leave-one-out validation, the background calculator seam |
| `Expiry/ExpiryCalculatorView.swift` | The screen |
| `Expiry/ExpiryFilmPickerView.swift` | The library-backed film picker |
| `Resources/Library/expiry-overrides.json` | Per-film departures from the group priors |
| `DarkroomTests/ExpiryEngineTests.swift` | 45 tests, mostly properties rather than fixed answers |

## Inputs

Three, and only three: the film (from the existing library, or an unlisted stock
typed in), the printed expiration date, and the storage. The default interface
asks for one storage tier, which means "the whole life was spent like that".
Underneath, storage is a timeline of segments, each with a tier and a share of
the life; a disclosure on the screen lets a roll that moved be described
properly. Fractions are read as proportions, so they need not sum to exactly one.

An unknown storage history is a mixture — mostly room temperature, with the
extremes still possible — not an assumption that the roll boiled in a car.

## Output

- Median exposure index and a P10–P90 range, both on the standard third-stop
  ladder (`EI 40 – 80 · best EI 50`). The ladder is `ExpiryEILadder`: index 0 is
  box speed, each index is a third of a stop, and only those values are ever
  shown.
- Stops of compensation, taken from the median.
- A confidence badge, capped by the evidence behind the numbers.
- One paragraph of plain language.
- A saturation state, when the shoulder can no longer deliver a shadow above the
  fog floor at all.
- Bracketing advice when the range or the confidence warrants it.
- Colour crossover and acetate degradation warnings, both explicitly *not*
  fixable by exposure.

## How the numbers are produced

**Manufacture date.** `expiration − shelf life`, where shelf life is a
distribution, not a value. Its centre and spread come from the film family and
are widened for older dating conventions: a film dated before 1985 is given a
55% longer nominal shelf life and slightly less effective stabilisers, because
both were true of coatings of that period. The date typed on the box is a fact;
the coating date is inferred, and the model says so.

**The curve.** A parametric Hurter–Driffield curve: base fog, a smooth toe
(`toe × log10(1 + 10^(x/toe))`), a gamma-scaled straight line, and an
exponential shoulder approaching `maxDensity`. Both branches are monotone, which
lets the engine invert the curve by bisection.

Ageing moves four things, each along a saturating exponential with its own time
constant: fog rises toward a ceiling, gamma falls, `maxDensity` falls, and the
speed point shifts. Fog is treated as developed silver, so it also subtracts
from the maximum density the shoulder can deliver — which is what makes
saturation appear on its own rather than as a flag someone added.

**Compensation** is the difference between the exposure the aged film needs to
put a shadow a fixed density above its fog, and the exposure the fresh film
needed. The shadow criterion widens with fog, because fog carries granularity
and a foggier film needs more separation for detail to read. If no exposure
reaches the criterion, or the result passes the family's saturation point, the
answer is marked saturated.

Damage accrued before the printed date is the manufacturer's own tolerance, so
it is subtracted: compensation is the change *since* expiry. That is why a film
months past its date barely moves.

**Thermal ageing** is Arrhenius. Each storage segment draws a temperature from
its band's distribution (mean, spread, and seasonal swing folded into the
spread), the rate for that draw is computed against a 17.5 °C reference, and the
rates are averaged *weighted by share of life*. Averaging rates rather than
temperatures is what makes a hot spike cost more than the same warmth spread out.

With the default activation energies the relative rates come out roughly where
the photographic literature describes them: about 0.03× frozen, 0.3× in a
fridge, 1× in a cool room, 1.5× in a warm room and around 3× in an attic. Those
multipliers are a *calibration choice*: the activation energy was picked so the
model reproduces them, not measured for any film.

**Radiation ageing** is modelled separately and never switched off by cold
storage. It is `max(floor, base × sensitivity) × years`, with a frozen
multiplier of 0.8 and a floor of 0.0012 log D per year, so a freezer slows it
and cannot stop it. ISO informs the sensitivity prior; it is not treated as a
measurement of it.

**Monte Carlo.** 2,000 samples by default, seeded with an FNV-1a hash of the
film key, the expiry day and the storage timeline, so the same inputs always give
the same answer. Storage, shelf life, activation energy and radiation
sensitivity vary together within each sample, which is the correlated-uncertainty
requirement: they are drawn per sample, not independently averaged. A closed-form
fast path (`quickEstimate`) runs on the main thread so the screen never waits for
the full run, and the full estimate replaces it a moment later.

A one-at-a-time sensitivity pass then re-runs the model varying storage, shelf
life and material separately, so the explainability section can name the input
that actually drives the spread instead of guessing.

## Behaviour groups

Every film in the library lands in exactly one group, by a rule that reads its
process, its ISO and its name:

| Group | Placed there by |
| --- | --- |
| Slow modern B&W | B&W under ISO 200 whose name carries a modern marker: T-Max, Delta, Acros, Pan F, Retro 80, P30, CMS 20, Ortho |
| Classic B&W | B&W under ISO 400 without those markers — FP4, HP5, APX, Fomapan, Neopan, ORWO |
| Fast B&W | B&W at ISO 400 and above — Tri-X, Delta 400/3200, T-Max 400/P3200, HP5 |
| Consumer colour negative | C-41 that is not a professional name — Gold, ColorPlus, Superia, C200, Pro Plus |
| Professional colour negative | C-41 whose name is Portra, Ektar, 400H, Reala, Vericolor, Ultra Color |
| Slide / E-6 | Every reversal stock |
| Cine / ECN-2 | Every cinema negative, and the respools cut from it |
| Other / unknown | The fallback for anything a future import adds that the rules cannot place |

A film not in the library at all runs as `other`: conservative distributions, an
assumed evidence class, and an answer labelled *Educated guess*. It cannot crash
the engine, and it cannot sound certain.

Per-film overrides (`expiry-overrides.json`) move a film's numbers inside its
group and may move its group. The bundled table covers T-Max 100, Delta 100,
Acros II, Pan F, HP5 Plus, FP4 Plus, Tri-X, Delta 400, Delta 3200, T-Max P3200,
Portra 160/400/800, Ektar 100, Gold 200/400, ColorPlus 200, Superia X-TRA 400,
Pro 400H, Velvia 50/100, Ektachrome E100, Vision3 50D/200T/250D/500T and Vision
5279/5274. Everything else runs on its group's priors — which is the honest
default, not a gap.

## Evidence and confidence

Every parameter is classified as measured, manufacturer documented, literature
derived, empirically observed or assumed. The class caps the confidence score,
so a tight simulated range built on assumptions cannot present itself as *Well
documented*. The score combines the evidence weight, how certain the storage
history is, and how wide the simulated range came out; the badge is `≥ 0.74`
well documented, `≥ 0.48` community consensus, otherwise an educated guess.

The caps matter more than the thresholds. A film placed by the catalogue rules
carries *literature derived* or *empirically observed* evidence, whose caps are
0.72 and 0.68 — below the well-documented threshold — so an aged film will read
*Community consensus* even when its simulated range is narrow and its storage is
known. Only document-backed evidence, or a roll still inside its printed date,
can reach *Well documented*. That is deliberate: nothing in the public record
documents a per-film ageing rate, and the badge must not imply otherwise.

The confidence the model has in *its own arithmetic* is not the confidence a
reader should have in an individual roll. That is why the disclaimer is not
dismissible and why bracketing appears whenever the range or the badge says so.

## Calibration

`ExpiryCalibrationPoint` records: film, family, estimated age, storage, the EI
used, a 1–5 quality score, the evidence type, a source, notes and an ordinal
outcome (under / right / over). The analyser shrinks each level toward the one
above it with a prior expressed in pseudo-observations — twenty at each level —
so a single controlled roll moves the prediction by about a twentieth of a stop
and it takes dozens to approach the hard clamp of ±0.5 stops.

Validation never fits on the data it reports. Rolls are sorted by date and the
most recent fifth is held out entirely — `ExpiryCalibrationStore.split` — so the
hold-out error is measured on rolls the fit has not seen. Fewer than five rolls
cannot be split usefully, so everything fits and the hold-out figure stays
unknown rather than being quietly computed on the training data. Leave-one-out
runs as well, over the fitting set only, and the research observation supplied
with the model (the reported 2009 T-Max 100 roll) is never used for validation at
all — it is a low-weight point in the fit, exactly as the request asked.

## What this model does not do

- It does not measure anything. Every coefficient is an engineering prior.
- It cannot know the roll's real storage, and humidity is implied by the tier
  rather than modelled.
- It cannot separate thermal fog from radiation fog in the public record, so the
  split is an assumption with a documented floor.
- It cannot model chemical degradation beyond fog, gamma loss and density loss:
  dye coupling loss, hardener exhaustion, latent-image keeping, or the way a
  badly kept colour film's layers can drift apart unevenly. Colour layer
  behaviour is approximated by one crossover-sensitivity number per family, and
  the app says the correction is beyond exposure rather than pretending
  otherwise.
- It cannot see physical damage: scratches, pressure marks, a buckled or
  vinegar-touched acetate base, or prior exposure.
- Past about four decades, the curves are extrapolation and the screen says so.

## Tuning and extending

- A new group: add a case to `ExpiryBehaviourGroup`, a prior to
  `ExpiryModel.defaultGroups`, and a rule to `ExpiryCatalogue.ruleGroup`.
- A new film reading: add an entry to `expiry-overrides.json`. No code change,
  and the record carries its own evidence class and note.
- A new storage tier: add a case with its `ExpiryClimate`; the unknown mixture is
  weighted separately.

Both paths keep the structure Codable and keep the evidence beside the number.



## Sources consulted

These were read while the model was built and are cited beside the parameters in
`ExpiryParameterCatalogue` (`Expiry/ExpiryParameters.swift`) and listed in the
app under **Sources**. They are used for the *direction* and the *band*, never
as a per-emulsion ageing rate, because none of them publishes one.

- **Kodak Publication E‑30, _Storage and Care of KODAK Photographic Materials —
  Before and After Processing_ (2004).** "Some photographic characteristics —
  speed, contrast, color balance, and fog level — change gradually after
  manufacture. Adverse storage conditions accelerate these changes. Color
  materials are more seriously affected than black-and-white materials because
  adverse conditions usually affect the emulsion layers to different degrees."
  Black-and-white storage table: up to 2 months below 24 °C, 6 months below
  16 °C, 12 months below 10 °C; professional colour refrigerated at 13 °C or
  lower; motion-picture film at 13 °C for up to three months, −18 to −23 °C for
  long term; 30–50% RH for re-sealed packages. Kodak's own host for E‑30 no
  longer resolves; the quoted copy is a mirror hosted by the *Timeline of
  Historical Colors in Photography and Film* research project.
- **Kodak Technical Information Bulletin TIB5202, _Storage and Handling of
  Unprocessed Film_ (May 2002).** "Naturally occurring gamma radiation increases
  the D‑min and toe densities and also increases grain. Higher-speed films are
  affected more by gamma radiation than lower-speed films." And: "While storage
  in a refrigerator or freezer can be highly beneficial, you should not rely on
  it to extend film life beyond the 'Develop Before' date… Neither cooling nor
  lead-foil bags will prevent this effect." Storage: 13 °C general, −18 °C
  beyond six months, about 50% RH.
- **Kodak Alaris, _KODAK PROFESSIONAL T‑MAX 100 Film_, F‑4016 (February 2016).**
  "Store unexposed film at 75 °F (24 °C), or lower, in the original sealed
  package." Cited beside the T‑Max 100 entry.
- **Ilford Photo, _ILFORD film FAQs_.** Asked whether out-of-date film is usable:
  "We do not recommend using films beyond their expiry date since performance is
  unlikely to be optimum… it is impossible to know the conditions under which a
  film will be stored during its lifetime. i.e refrigerated films may last much
  longer. If a film has not been refrigerated, then the expiry date is a useful
  guide." No numeric shelf life is published — which is why the shelf-life
  distribution is classed as an assumption.
- **HARMAN technology, _ILFORD DELTA 3200 PROFESSIONAL — Technical Information_
  (June 2025).** "store DELTA 3200 Professional in a cool (10–20 °C/50–68 °F),
  dry place in its original packaging. DELTA 3200 Professional may be stored in
  a fridge/freezer but allow plenty of time for the film to acclimatise."
- **Image Permanence Institute, _IPI Storage Guide for Acetate Film_ (Reilly,
  1993).** "At 60 °F, 50% RH the free acidity will double in ten years, at 20%
  RH, it will double in 45 years"; "At 55 °F, 40% RH … the prediction for onset
  of vinegar syndrome for fresh film is 150 years"; "the reactions of vinegar
  syndrome will take about 17 times longer at 30 °F than at 70 °F"; and the
  order of symptoms — "the first sign is usually the vinegar odor", later
  "brittleness and channeling of the emulsion". This is acetate *base*
  hydrolysis, not emulsion speed loss, and the model quotes it as context rather
  than using its coefficient.
- **National Film Preservation Foundation, _The Film Preservation Guide_,
  chapter 6, "Storage".** "Fresh acetate film stored at a temperature of 65 °F
  and 50% RH will last approximately 50 years before the onset of vinegar
  syndrome. Just reducing the temperature 15°, while keeping the humidity at the
  same level, delays the first signs by 150 years."
- **Library of Congress, _Care, Handling and Storage of Photographs_.** "A
  relatively dry (30–50% relative humidity), cool (70 °F or below), and stable
  environment is best. Avoid storage in attics; basements…"; for colour
  negatives, "Storage at low temperatures (40 °F or below) is recommended."
- **US Department of the Air Force, AFM 160‑30 (15 November 1965), p. 18‑5.**
  "As films age, they lose speed and contrast." The closest thing found to a
  published, non-forum statement of the two effects this model is built around.

Two honest gaps: no manufacturer publishes a numeric shelf life for a still
film, and no free source found states a per-emulsion ageing rate. Both are
therefore labelled assumptions in the model rather than dressed up as data.
Reddit and Photrio threads were deliberately not used as sources: they are
uncontrolled anecdotes, and converting them into coefficients would be the
fabrication the request asked to avoid. The one anecdotal observation in the
calibration — the 2009 T‑Max 100 roll — is recorded as exactly that, weighted
below any controlled result, and is never used for validation.
