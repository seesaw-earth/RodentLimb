# Scoring conventions for itch, seizure, spontaneous pain and grooming in mice

Reference note for the RodentLimb behaviour modules. Compiled 2026-11-02.
Setup assumed: mouse filmed from below through a transparent floor, 7 keypoints (L/R forepaw, L/R hind paw, tail base, nose, mouth), 30–60 fps.

**Verification legend**
- **[V]**: checked against the primary paper, protocol text or database record during this research. Short quotes are verbatim.
- **[2]**: checked only through a secondary source that cites the original (a review, protocol or citing paper).
- **[U]**: NOT verified. This is from memory or my own inference. Check it before you cite it or hard-code it.
- *derived*: arithmetic I did on verified numbers.

---

## 0. Points that apply to all four modules

| Issue | Implication |
|---|---|
| Hind-paw scratch strokes run at about 20 Hz [V, Elliott 2017]. | At 30 fps the Nyquist limit is 15 Hz, so strokes alias to about 10 Hz (*derived*: abs(20 − 30) = 10). You cannot count strokes at 30 fps. Detect **bouts** from the bout envelope instead: paw lift, paw moving toward the head, high-velocity jitter and drops in keypoint confidence. 60 fps (Nyquist 30 Hz) can resolve strokes. Elliott et al. note that scratch frequency is close to video frame rates ("20 Hz vs. 33 Hz"). |
| Phase-1 face-grooming strokes: 5–10 strokes in about 1 s [V, Berridge 2005]. That is about 5–10 Hz (*derived*). | Barely resolved at 30 fps; comfortable at 60 fps. |
| Units the field expects | Itch: **bout counts**, in 5-min bins and as a total. Formalin and capsaicin: **cumulative seconds of licking/biting** per phase and per bin. Seizures: **latencies (s)** to defined endpoints, **maximum stage** per animal, and **% of animals reaching each stage**. Grooming: **total seconds**, **number of bouts**, **% incorrect transitions** and **% interrupted bouts**. |
| Two existing bottom-up systems match your geometry | Scratch-AID (30 fps, bottom view) [V] and Wotton et al. 2020 JAX formalin (30 fps, bottom view) [V]. LUPE uses bottom-up infrared, 20 keypoints, 60 fps [V/2]. |

---

## A. Itch: scratching in mice

### A1. Operational definitions
- **Classic bout** (Kuraishi lineage, the most cited wording): "A single scratch bout was defined as one or more rapid back-and-forth motions of the hindpaw directed at the injection site", which "ends with either a pause, licking, or biting of the toes or placing of the hindpaw on the floor." [V, Valtcheva et al. 2015]
- **Kuraishi et al. 1995 lineage**: "A series of scratching behaviors was counted as one bout of scratching". Only hind-paw scratching of the injected site is counted. [2, Akimoto & Furuse 2011, who cite Kuraishi 1995]
- **Cheek model, JoVE protocol**: "Mice raise a hind leg towards the cheek and scratch several times over one or a few seconds, then put their leg down." That whole leg-up sequence counts as one bout. Scratching of other sites is not counted. A **wipe** is a stroke by a single foreleg (pain-like). Strokes with both forelegs are grooming and are not counted. [V, Yamanoi et al. 2019]
- **Shimada & LaMotte 2008 (cheek model)**: hind-limb scratching of the cheek indicates itch, and unilateral forelimb wiping indicates pain. The PMC full text was blocked, so I could not quote their exact definitions [U for exact wording]. A follow-up from the same field confirms the dissociation: histamine "elicited dose-related hindlimb scratching bouts with little forelimb wiping", while capsaicin "elicited dose-related forelimb wiping with little scratching" [V, Akiyama et al. 2010 abstract].
- **Calf model** (relevant if you inject a hind limb): pruritogens in the calf evoke **biting** of the site, and algogens evoke **licking** [V, Akiyama et al. 2014 abstract; LaMotte et al. 2011].
- **Scratch-AID "scratching train"** [V, Yu et al. 2022]:
  - Definition: "Each episode of scratching, here defined as a scratching train."
  - Four phases: (1) start, when the mouse begins lifting the hind paw; (2) scratching bout, the "rhythmic movement of hind paw against the affected skin"; (3) paw licking; (4) end, when the paw returns to the floor or enters the mouth.
  - Separating trains: the paper cites a field consensus of "'2s' as the threshold" (Darmani & Pandya 2000 [U, not retrieved]).
- **MicroAct** (magnet on the hind paw plus a coil): an event is "consecutive scratching behavior (events) consisting of 3 or more beats". Event counts were "almost comparable" to an observer's. [V, Inagaki et al. 2003 abstract] The Hz criteria are in the paywalled full text [U].
- **Acoustic detection**: a bout is "a series of individual hindpaw-mediated scratches (typically three to six) in rapid succession" [V, Elliott et al. 2017]. This is a finer unit than the classic lift-to-floor bout; one classic bout can contain several acoustic bouts.
- **SCLABA** (Noveltec; video with colour-marked paws): source not retrieved [U].

### A2. Standard measures, windows and bins
- **Primary measure**: number of bouts over the session, plus a time course in **5-min bins**. Some labs also report total scratching time or number of trains.
- **Observation period after the pruritogen**:
  - **30 min** is the standard: Valtcheva 2015 [V]; Akimoto & Furuse 2011 [V]; the JoVE cheek protocol scores "every 5 min for a total of 30 min" [V].
  - 20 min also appears: LaMotte 2011 cheek model [V]; Scratch-AID recordings [V].
  - Chronic models use longer or repeated sessions.
- **Pre-test habituation**:
  - 2 h with white noise [V, Valtcheva].
  - 5 min [V, Scratch-AID].
  - The nape is shaved 1 day before testing [V, Valtcheva].
- **Video**: 30–60 fps (JoVE) [V]. Scratch-AID used 30 fps from below, 720×720 px [V].

### A3. Numbers for detection rules
| Quantity | Value | Source |
|---|---|---|
| Hind-paw stroke rate | Period about 50 ms, so about 20 Hz | [V] Elliott 2017 |
| Acoustic bout duration | "between 200 and 500 ms but can be as long as a full second", 3–6 strokes | [V] Elliott 2017 |
| Scratch+lick cycle within a train (CQ, nape) | "around 30 frames" at 30 fps, about 1 s (*derived*) | [V] Scratch-AID |
| Mean train length | About 280 frames (about 9 s) for CQ nape; about 53 frames (about 1.8 s) for chronic SADBE | [V] Scratch-AID (summarised from text) |
| Gap that separates trains | 2 s | [V] cited as consensus in Scratch-AID |
| Minimum event | 3 or more beats | [V] MicroAct |
| Histamine, 1 mg in 50 µl, nape (WT, C57BL/6 background) | 121.4 ± 12.8 bouts / 30 min | [V] Valtcheva 2015 |
| Chloroquine, 200 µg in 50 µl, nape | 163.7 ± 22.6 bouts / 30 min | [V] Valtcheva 2015 |
| β-alanine, 223 µg, nape | 57.0 ± 10 bouts / 30 min | [V] Valtcheva 2015 |
| Common doses | CQ 200 µg (15–50 µl) [V]; histamine 50 µg/10 µl cheek [V, JoVE]; 10–50 µg cheek [V, LaMotte 2011]; 100–200 µg/15 µl nape [V, Scratch-AID] | as listed |
| Compound 48/80 counts in C57BL/6 | Not verified. Doses of about 50–100 µg per nape site are common [U]. | — |
| Latency to first bout; vehicle counts | Not verified. Scratching usually starts within about 1 min of an intradermal pruritogen, most of it falls in the first 10–15 min, and saline gives few bouts [U]. Calibrate on your own controls. | — |

Human scorers are not a perfect gold standard. Against frame-by-frame ground truth, manual precision was 94.2% for CQ nape, 80.5% for histamine and 66.3% for SADBE [V, Scratch-AID].

### A4. Known confounds
- **Injection pain versus itch**: cheek wiping, or licking in the calf/hind-paw models. Score scratching and wiping/licking separately.
- **Grooming-associated scratching**: scratching is part of the normal cephalocaudal grooming repertoire [V, Kalueff 2016]. Count only scratching aimed at the injection site.
- **Strain**: C3H/HeJ shows "generalized resistance to pruritogen-induced scratching" (paper title, Green et al. 2006 [U, details not retrieved]). Sex, time of day, observer presence, shaving, habituation and injection volume and depth also matter.
- **Bottom view**: the contact point at the nape or cheek is hidden. The hind paw moves forward toward the head and often loses tracking confidence. At 30 fps the 20 Hz strokes alias (section 0).

### A5. Key references
1. Kuraishi Y, Nagasawa T, Hayashi K, Satoh M (1995). Scratching behavior induced by pruritogenic but not algesiogenic agents in mice. *Eur J Pharmacol* 275:229–233. DOI 10.1016/0014-2999(94)00780-B. [citation V via Kuraishi 2015 reference list; DOI U]
2. Shimada SG, LaMotte RH (2008). Behavioral differentiation between itch and pain in mouse. *Pain* 139(3):681–687. DOI 10.1016/j.pain.2008.08.002. [citation 2; DOI U]
3. Akiyama T, Carstens MI, Carstens E (2010). Differential itch- and pain-related behavioral responses and µ-opioid modulation in mice. *Acta Derm Venereol* 90(6):575–581. DOI 10.2340/00015555-0962. [V]
4. Valtcheva MV, Davidson S, Zhao C, Leitges M, Gereau RW IV (2015). Protein kinase Cδ mediates histamine-evoked itch and responses in pruriceptors. *Mol Pain* 11:1. DOI 10.1186/1744-8069-11-1. [V; last author U]
5. Yu H, Xiong J, Ye AY, … Luo W (2022). Scratch-AID, a deep learning-based system for automatic detection of mouse scratching behavior with high accuracy. *eLife* 11:e84042. DOI 10.7554/eLife.84042. [V]
6. Elliott P, G'Sell M, Snyder LM, Ross SE, Ventura V (2017). Automated acoustic detection of mouse scratching. *PLoS ONE* 12(7):e0179662. DOI 10.1371/journal.pone.0179662. [V]
7. Inagaki N, Igeta K, Shiraishi N, Kim JF, Nagao M, Nakamura N, Nagai H (2003). Evaluation and characterization of mouse scratching behavior by a new apparatus, MicroAct. *Skin Pharmacol Appl Skin Physiol* 16(3):165–175. DOI 10.1159/000069755. [V]
8. Yamanoi Y, Kittaka H, Tominaga M (2019). Cheek injection model for simultaneous measurement of pain and itch-related behaviors. *J Vis Exp* (151):e58943. DOI 10.3791/58943. [V]

Also useful:
- LaMotte RH, Shimada SG, Sikand P (2011). *Exp Dermatol* 20(10):778–782. DOI 10.1111/j.1600-0625.2011.01367.x. [V]
- Liu Q et al. (2009). Sensory neuron-specific GPCR Mrgprs are itch receptors mediating chloroquine-induced pruritus. *Cell* 139(7):1353–1365. DOI 10.1016/j.cell.2009.11.034. [V]

---

## B. Seizures: PTZ, kainic acid, pilocarpine

### B1. Scales and their exact stage definitions

**Racine (1972)**: the original scale, from rat amygdala kindling [V via two secondary sources]:
1. Mouth and facial movements.
2. Head nodding.
3. Forelimb clonus.
4. Rearing (with forelimb clonus).
5. Rearing and falling, i.e. loss of postural control (a generalized motor convulsion).

**Lüttjohann, Fabene & van Luijtelaar (2009) is a RAT scale.** The title is "A revised Racine's scale for PTZ-induced seizures in **rats**". It used Wistar rats given PTZ at 20 mg/kg, then +10 mg/kg every 15 min until a 5-min convulsive seizure [V]. It is not a mouse scale. The six categories are commonly reproduced as follows [U for verbatim wording]:
1. "sudden behavioral arrest and/or motionless staring"
2. "facial jerking with muzzle or muzzle and eye"
3. "neck jerks"
4. "clonic seizure in a sitting position"
5. "convulsions including clonic and/or tonic–clonic seizures while lying on the belly and/or pure tonic seizures"
6. "convulsions including clonic and/or tonic–clonic seizures while lying on the side and/or wild jumping"

**Van Erum, Van Dam & De Deyn (2019)**: the revised Racine scale for **mice** given PTZ. It extends Lüttjohann's scale to run from −1 to 7.

What I verified in the text [V]:
- Stage 0 = whisker trembling during an electrographic seizure.
- Stage 1 = behavioural arrest.
- Stage 7 = "tonic extension of the muscles, which, if prolonged, can lead to the death of an animal."
- "Scores 0 to 2 represent partial/focal seizures, and stages 3 to 6 are generalized seizures."
- Stage −1 = non-convulsive animals.

Stages 2–6 below are reconstructed from the paper's verified list of behaviours, because the stage table is in Figure 1 and could not be extracted:

| Score | Behaviour | Status |
|---|---|---|
| −1 | Non-convulsive | [V] |
| 0 | Whisker trembling | [V] |
| 1 | Sudden behavioural arrest / motionless staring | [V] |
| 2 | Facial jerking ("expressed with the nose") | [V behaviour / U mapping] |
| 3 | Neck jerks (myoclonic) | [V behaviour / U mapping] |
| 4 | Clonic seizure while falling into a sitting position | [V behaviour / U mapping] |
| 5 | Clonic or tonic–clonic seizure lying on the belly, without loss of balance | [V behaviour / U mapping] |
| 6 | Clonic or tonic–clonic seizure falling on the side, and/or wild jumping | [V behaviour / U mapping] |
| 7 | Tonic extension (forelimbs alone, or fore- and hindlimbs), then respiratory arrest or death | [V] |

Other verified details from Van Erum 2019 [V]:
- Single i.p. doses of 10–80 mg/kg.
- Observation for at least 1 h, ended after 15 min of normal behaviour and EEG, with a maximum of 2 h.
- An EEG seizure was defined as lasting at least 5 s. Events less than 5 s apart were merged into one event.
- Only about 25% of PTZ deaths (11/41) showed tonic extension of the hindlimbs. It was commoner in 3-month-old mice (9/14) than in 12–15-month-old mice (2/27).
- In the other animals, "the hindlimbs remained clonic (trampling, kicking) until death".
- Every animal that died showed wild jumping first.

**A mouse 0–7 adaptation used in practice** (Front Mol Neurosci 2023; 15:1079097; authors not retrieved) [V table text]:
- 0: "Normal behavior"
- 1: "Hypomobility, behavioral arrest, loss of posture, or immobility"
- 2: "Isolated and focal myoclonic jerks including facial twitches"
- 3: "Strong myoclonic jerks including head nodding and unilateral forelimb jerks"
- 4: "Clonic seizure involving movements such as forelimb and facial clonus, with or without rearing"
- 5: "Tonic-clonic seizure involving clonus of all limbs while maintaining balance"
- 6: "Tonic-clonic seizure with loss of righting reflex (lying on side), and may include wild running and jumping"
- 7: "Tonic extension, possibly leading to respiratory arrest, and death"

**Common Racine-type scale for PTZ kindling in mice** (as reproduced in a 2025 bioRxiv on PTZ dose escalation, scored for 30 min after each injection) [V text; citation incomplete]:
- 0: no response
- 1: behavioural arrest or slowing
- 2: head nodding with facial clonus
- 3: partial limb clonus, with or without tail stiffening
- 4: clonic seizure with rearing and loss of posture
- 5: generalized tonic–clonic seizure with wild running and/or jumping
- 6: death

**Kainate, mouse** (Schauwecker & Steward 1997, adapted from Racine) [V]:
- "Stage 1: immobility; stage 2: forelimb and/or tail extension, rigid posture; stage 3: repetitive movements, head bobbing; stage 4: rearing and falling; stage 5: continuous rearing and falling; stage 6: severe tonic-clonic seizures."
- Kainate 30 mg/kg s.c.; mice watched continuously for 4 h.

Sharma et al. (2018) use a 5-stage modified Racine scale for kainate in mice and rats [V]:
1. Absence-like immobility.
2. Hunching with facial automatisms and/or abducted forelimbs.
3. Rearing with facial automatisms and forelimb clonus.
4. Repeated rearing with continuous forelimb clonus, then falling (loss of righting reflex).
5. Generalized tonic–clonic convulsions with lateral recumbency or jumping (jumping is commoner in mice), or wild running followed by generalized convulsions.

Stages 1–2 are non-convulsive; stages 3–5 are convulsive.

**Pilocarpine**: scored with Racine-type progression [V, Curia et al. 2008]:
- Status epilepticus (SE) is conventionally at least 30 min of continuous seizure activity.
- Mice receive 300–350 mg/kg. Mortality from clonic–tonic seizures was 25% at 325 mg/kg, 50% at 350 mg/kg and 100% at 400 mg/kg.
- At 200–300 mg/kg, mice were motionless, with tremor and sometimes hindlimb myoclonus.

### B2. Endpoint definitions you can implement from below
- **First myoclonic jerk / Straub tail**: "a tonic dorsal extension of the tail usually accompanied by a jerk or jump of the animal's entire body" [V, Copping & Silverman 2021].
- **Loss of righting**: "the absence of both fore- and hindlimb paws from the surface of the cage bottom for >1-sec" [V, Copping & Silverman 2021]. This maps directly to a bottom-view rule: no paw keypoints in floor contact for more than 1 s.
- **Generalized clonic–tonic seizure**: "loss of righting followed by phases of rigidity and forelimb/hindlimb spasms" [V, Copping & Silverman 2021].
- **Partial (focal) clonus**: clonic activity of the face, head and/or forelimbs, typically lasting 1–2 s [V, Ferraro 1999, summarised from text].
- **Generalized clonus**: sudden loss of upright posture, whole-body clonus of all four limbs and tail, with rearing and autonomic signs [V, Ferraro 1999, summarised from text].
- **Maximal seizure**: a "generalized seizure characterized by tonic hindlimb extension" [V, Ferraro 1999].
- **Tonic hindlimb extension (THE)**: the MES-test endpoint. Protection is defined as "abolition of the hindlimb tonic extensor component of the seizure" [V, NINDS ETSP]. The common "hindlimbs at 180° to the body plane" criterion was not found in a retrieved source [U].
- **NINDS s.c. PTZ test endpoint**: "clonic spasms of the fore and/or hind limbs, jaws, or vibrissae" lasting "approximately 3 to 5 seconds", within 30 min [V].
- **NINDS i.v. PTZ threshold test**: latency to "first twitch" and to "onset of sustained clonus" [V].
- **Wild running / "popcorning"** (flurothyl scale): after regaining the righting reflex, the mouse runs wildly and jumps erratically. This is a brainstem seizure, graded 3 to 7, with grade 6 = stiff extension of both hindlimbs and grade 7 = death [V, Bio-protocol 2017].
- **Freezing / behavioural arrest** in one automated JAX pipeline: at least 3 s with average speed below 0.01 cm/s [V, Kumar-lab bioRxiv 2024; full citation not retrieved].

### B3. Standard measures, windows and numbers
- **Measures**:
  - Latency (s) to first myoclonic jerk or twitch, to generalized clonic seizure (with loss of righting), and to THE.
  - Maximum stage per animal.
  - % of animals reaching each stage.
  - Seizure duration.
  - Mortality.
- **Observation periods**:
  - 30 min: NINDS s.c. PTZ [V]; Copping 2021, 80 mg/kg i.p. [V]; kindling sessions [V].
  - 45 min: Ferraro 1999 [V].
  - 20 min: JAX video study [V].
  - 1–2 h when EEG is recorded: Van Erum [V].
  - 4 h or more: kainate [V].
  - Hours: pilocarpine status epilepticus [V].
- **Doses**:
  - NINDS s.c. CD97 dose: **85 mg/kg for CF-1 mice and 45 mg/kg for C57BL/6** [V].
  - Ferraro s.c. **80 mg/kg** [V].
  - Kainate in C57BL/6J: 20–30 mg/kg i.p. single dose, convulsive SE onset 5–49 min [V, Sharma 2018]; or 5 mg/kg every 30 min [V].
- **Typical latencies, Ferraro 1999, 80 mg/kg s.c.** (table layout was garbled; this is my best reading) [V]:

| Strain | Partial clonus | Generalized clonus | THE |
|---|---|---|---|
| C57BL/6J | 8.67 min | 15.7 min | 0% of mice |
| DBA/2J | 3.95 min | 4.42 min | 16.7 min (90% of mice) |

  C57BL/6J is relatively PTZ-resistant. Expect few or no THE events.
- **Clonus frequency (Hz) and myoclonic-jerk duration**: no validated behavioural value for mice was found [U]. Treat a myoclonic jerk as a single sub-second whole-body or neck event. Treat clonus as rhythmic limb oscillation sustained for at least about 3–5 s (the NINDS endpoint). Fit the frequency band to your own labelled videos.

### B4. Confounds
- **Biology and protocol**:
  - Strain: B6 is resistant and DBA/2 sensitive [V].
  - Age: young mice are less susceptible but show more THE [V].
  - Also sex, route (s.c., i.p. or i.v.), and vendor or batch (kainate) [V, Sharma].
- **Behaviour versus EEG**: about 50% of behavioural seizures in C57BL/6J did not match epileptiform EEG [V, Sharma 2018].
- **Mimics**:
  - Grooming can look like facial clonus.
  - Hind-limb **scratching** is rhythmic and can look like clonus.
  - Also head shakes, startle, sleep twitches, and voluntary lying (versus loss of righting).
- **Humane endpoints shorten observation**: Van Erum intervened in convulsions longer than 5 min [V]. The JAX study euthanised at a score above 3 sustained for 1 min [V].
- **Bottom view**:
  - Lateral recumbency changes which paws are visible.
  - THE puts the hind paws caudal to the tail base and keeps them rigid (low variance).
  - Jumping removes all paws from view.

### B5. Key references
1. Racine RJ (1972). Modification of seizure activity by electrical stimulation. II. Motor seizure. *Electroencephalogr Clin Neurophysiol* 32(3):281–294. DOI 10.1016/0013-4694(72)90177-0. [V]
2. Lüttjohann A, Fabene PF, van Luijtelaar G (2009). A revised Racine's scale for PTZ-induced seizures in rats. *Physiol Behav* 98(5):579–586. DOI 10.1016/j.physbeh.2009.09.005. [V]
3. Van Erum J, Van Dam D, De Deyn PP (2019). PTZ-induced seizures in mice require a revised Racine scale. *Epilepsy Behav* 95:51–55. DOI 10.1016/j.yebeh.2019.02.029. [V]
4. Ferraro TN, Golden GT, Smith GG, St Jean P, Schork NJ, Mulholland N, Ballas C, Schill J, Buono RJ, Berrettini WH (1999). Mapping loci for pentylenetetrazol-induced seizure susceptibility in mice. *J Neurosci* 19(16):6733–6739. DOI 10.1523/JNEUROSCI.19-16-06733.1999. [V]
5. Schauwecker PE, Steward O (1997). Genetic determinants of susceptibility to excitotoxic cell death: implications for gene targeting approaches. *PNAS* 94(8):4103–4108. DOI 10.1073/pnas.94.8.4103. [V]
6. Curia G, Longo D, Biagini G, Jones RSG, Avoli M (2008). The pilocarpine model of temporal lobe epilepsy. *J Neurosci Methods* 172:143–157. DOI 10.1016/j.jneumeth.2008.04.019. [V]

Also useful:
- Sharma S, Puttachary S, Thippeswamy A, Kanthasamy AG, Thippeswamy T (2018). *Front Neurol* 9:7. DOI 10.3389/fneur.2018.00007. [V]
- Copping NA, Silverman JL (2021). Abnormal electrophysiological phenotypes and sleep deficits in a mouse model of Angelman Syndrome. *Mol Autism* 12. DOI 10.1186/s13229-021-00416-y. [V from the preprint; article number U]
- NINDS ETSP/PANAChE test descriptions for s.c. PTZ and MES (panache.ninds.nih.gov). [V]

---

## C. Spontaneous pain: formalin and capsaicin

### C1. Operational definitions
- **Licking/biting** (the main mouse measure):
  - Wotton 2020 (bottom-up, JAX): "any contact between the mouth and the right hind paw was scored as licking" [V]. Licking and biting were pooled.
  - Hunskaar & Hole 1987: "the amount of time the animals spend licking the injected paw" [V].
  - Mogil protocol: total time licking or biting the injected paw, by stopwatch [V].
  - Bio-protocol: "mice primarily show paw-licking behaviors" [V, Gong 2014].
- **Flinch / shake**: "a brisk elevation of the foot is scored as a single flinch". Rapid runs of flinches that cannot be counted individually are scored as one [V, Gong 2014; this is the rat definition]. Flinch counting is mainly a rat measure. In mice it is secondary to licking.
- **Weighted pain score**, Dubuisson & Dennis 1977 (rats and cats, forepaw injection [V, abstract]). Categories [U, from memory]:
  - 0 = normal weight bearing
  - 1 = injected paw favoured (rests lightly, limping)
  - 2 = paw elevated
  - 3 = licking, biting or shaking

  Score = (t1 + 2·t2 + 3·t3) / T. Saddi & Abbott (2000) analysed its scoring properties in mice [U, not retrieved].
- **Guarding**: there is no standard mouse definition in the chemical tests. Implement it as the injected hind paw lifted, or with reduced floor contact, outside licking episodes; this is about the same as Dubuisson–Dennis categories 1–2. Lopes 2019 excluded "Limping, altered locomotion or grooming of other parts of the body" [V].
- **LUPE** (Corder and Yttri labs) [V]:
  - High-speed infrared video "recorded from below through a glass floor", with 20 DeepLabCut keypoints.
  - Six behaviour classes: "Still, Walk, Rear, Groom, Lick Left Hindpaw, and Lick Right Hindpaw".
  - Behaviour probabilities in "1-minute bins over 30-minute sessions".
  - "thirty-second sliding windows" of transitions are clustered into 6 states. The Affective-Motivational Pain Scale (AMPS) is PC2 of state occupancy.
  - Stimuli: 1% or 5% formalin, or 2% capsaicin, in the left hind paw.
  - The chambers run at 60 fps [2, a 2025 Corder-lab bioRxiv describing LUPE].
  - LUPE separates grooming from paw-directed licking using motion energy.

### C2. Phase windows and bins in use
| Source | Formalin | Phase I | Phase II | Bins / total |
|---|---|---|---|---|
| Hunskaar & Hole 1987 [V] | 1%, dorsal hind paw | 0–5 min | 20–30 min | — |
| Mogil 1999 / JAX MPD protocol [V] | 5%, 25 µl, plantar | 0–10 min | 10–60 min | 5-min blocks / 60 min |
| Gong et al. 2014 (Bio-protocol) [V] | 5%, 10 µl (mouse) | 0–5 min | 20–40 min | 5-min periods |
| López-Cano et al. 2017 (Bio-protocol) [V] | 2.5% | first 5 min | after a 5–15 min quiescent period, 15–30 min | — |
| Lopes et al. 2019 (F1000Res refinement) [V] | 1.85%, 20 µl | 0–15 min | 15–45 min | — |
| Wotton et al. 2020 (JAX) [V] | 2.5%, 30 µl | 0–10 min (first 5 min excluded because of anaesthesia) | 20–45 min main; 10–60 min also used | 5-min bins / 90 min |
| Murray et al. 1988 [V] | dilute formalin | — | extended to 20–45 min | — |
| LUPE [V] | 1% or 5% | — | — | 1-min bins / 30 min |

**Recommended defaults**:
- Phase I = 0–10 min; Phase II = 10/15–60 min.
- 5-min bins; record 60 min.
- Let users re-window to 0–5 / 20–40 or 0–5 / 15–45.

### C3. Numbers
- **C57BL/6J males, 5% formalin 25 µl** (Mogil 1999 data in the JAX Mouse Phenome Database) [V]:

| Phase | Mean ± SD (s) | n | Range across 11 strains |
|---|---|---|---|
| Phase I (0–10 min) | 75.5 ± 15.3 | 7 | 34 s (A/J) to 120 s (C58/J) |
| Phase II (10–60 min) | 457 ± 211 | 7 | 32 s (A/J) to 470 s (CBA/J) |

- **Capsaicin**:
  - Mogil protocol: 2.5 µg s.c. in the hind paw, licking scored for 15 min [V]. C57BL/6J: 106 ± 55 s (n = 5) [V, MPD].
  - The classic mouse capsaicin test uses 1.6 µg/paw intraplantar with licking/biting [V for the dose, Sakurada 2003 abstract]. A 5-min observation window is usual [U].
- Anaesthesia at the time of injection reduced Phase I by about 90% [V, Lopes 2019].
- Wotton's 30 fps bottom-view classifier agreed with a human observer on about 98% of seconds. Inter-observer r = 0.98 [V].

### C4. Confounds
- **Injection conditions**:
  - Formalin concentration and volume.
  - Anaesthesia at injection, which suppresses Phase I.
  - Injection site (dorsal versus plantar).
  - Handling stress.
- **Animal**: strain and sex. C57BL/6J versus C57BL/6NJ shows a sex × strain interaction in Phase II [V, Wotton].
- **Environment**:
  - Ambient temperature [U, often cited from Tjølsen 1992].
  - Time of day; observer presence; mirrors versus camera view.
- **Grooming-chain licking versus pain licking**: separate them by paw identity, duration and context (LUPE).
- **Licking the uninjected paw**: score left and right separately.
- **Bottom view**:
  - Paw oedema changes the paw's shape.
  - During licking the mouth/nose keypoint sits over the hind paw, so occlusion is high.
  - Flinches are very brief. At 30 fps they last only a few frames, so keep debounce filters short.

### C5. Key references
1. Dubuisson D, Dennis SG (1977). The formalin test: a quantitative study of the analgesic effects of morphine, meperidine, and brain stem stimulation in rats and cats. *Pain* 4(2):161–174. DOI 10.1016/0304-3959(77)90130-0. [citation 2; DOI U]
2. Hunskaar S, Hole K (1987). The formalin test in mice: dissociation between inflammatory and non-inflammatory pain. *Pain* 30(1):103–114. DOI 10.1016/0304-3959(87)90088-1. [V]
3. Tjølsen A, Berge OG, Hunskaar S, Rosland JH, Hole K (1992). The formalin test: an evaluation of the method. *Pain* 51(1):5–17. DOI 10.1016/0304-3959(92)90003-T. [title V; volume, pages and DOI U]
4. Wotton JM, Peterson E, Anderson L, Murray SA, Braun RE, Chesler EJ, White JK, Kumar V (2020). Machine learning-based automated phenotyping of inflammatory nocifensive behavior in mice. *Mol Pain* 16:1744806920958596. DOI 10.1177/1744806920958596. [V]
5. James JG, McCall NM, Hsu AI, Oswell CS, … Yttri EA, Corder G (2026). Mimicking opioid analgesia in cortical pain circuits. *Nature* (published 7 Jan 2026). DOI 10.1038/s41586-025-09908-w. [V; volume and pages not retrieved] This is where LUPE was introduced. Preprint: bioRxiv 2024, DOI 10.1101/2024.04.26.591113. [V]
6. Mogil JS, Wilson SG, Bon K, Lee SE, Chung K, Raber P, Pieper JO, Hain HS, Belknap JK, Hubert L, Elmer GI, Chung JM, Devor M (1999). Heritability of nociception I: responses of 11 inbred mouse strains on 12 measures of nociception. *Pain* 80(1–2):67–82. DOI 10.1016/S0304-3959(98)00197-3. [V]

Also useful:
- Gong N et al. (2014). Pain assessment using the rat and mouse formalin tests. *Bio-protocol* 4(21):e1288. [V]
- Lopes DM et al. (2019). A refinement to the formalin test in mice. *F1000Research* 8:891. DOI 10.12688/f1000research.18338.2. [V]
- Murray CW, Porreca F, Cowan A (1988). *J Pharmacol Methods* 20(2):175–186. DOI 10.1016/0160-5402(88)90078-2. [V]
- Hunskaar S, Fasmer OB, Hole K (1985). Formalin test in mice, a useful technique for evaluating mild analgesics. *J Neurosci Methods* 14:69–76. [U]

---

## D. Self-grooming

### D1. Operational definitions
- **Syntactic chain phases** [V, Kalueff et al. 2016, Fig. 1a]:
  - Phase 1: "a series of elliptical bilateral paw strokes made near the nose".
  - Phase 2: "a series of unilateral strokes (each made by one paw)".
  - Phase 3: "a series of bilateral strokes backwards and upwards made by both paws simultaneously".
  - Phase 4: body licking.

  The chain "serially links 20 or more grooming movements into four distinct, predictable phases". It makes up only about 10–15% of grooming; the rest is flexibly ordered non-chain grooming.
- **Mouse phase timing** [V, Berridge et al. 2005]:
  - Phase I: "5–10 rapid elliptical forepaw strokes made with both paws simultaneously", lasting "about one second".
  - Phase II: "1–4 unilateral or highly asymmetrical strokes", "short (0.25 s)".
  - Phase III: "1–5 large bilateral strokes with both paws", 1–3 s.
  - Phase IV: "a 2–5 s bout of body licking directed to the flank".

  Chains were classified as perfect, imperfect, terminal substitution or incomplete. Scoring was frame by frame at 1/10 speed; sessions lasted 30 min.
- **Kalueff–Tuohimaa grooming analysis algorithm** (2004, 2005; Nature Protocols 2007):
  - It records region-by-region cephalocaudal progression: paw licking, nose/face wash, head wash, body grooming, leg licking, then tail/genital grooming [2, ConductScience ethogram; Kalueff 2016].
  - The usual numeric codes are 0 = no grooming, 1 = paws, 2 = nose/face, 3 = head, 4 = body, 5 = legs, 6 = tail/genitals. "Correct" transitions run 0→1→2→3→4→5→6→0 [U for the exact code numbers and transition list].
  - Its measures are [V]:
    - % incorrect transitions, i.e. "transitions that violate the cephalocaudal rule", as a percentage of all transitions;
    - % interrupted bouts;
    - % incomplete bouts (Smolinsky 2009);
    - regional distribution of grooming.

  Kalueff & Tuohimaa 2005 found that % non-cephalocaudal transitions and % interrupted bouts are "more reliable behavioural markers of stress bidirectionally sensitive" to diazepam and PTZ than frequency or duration [V].
- **The "6-s criterion" is NOT verified.** I could not find a 6-s bout or interruption threshold in any retrieved text. Thresholds that were verified:
  - Estanislau 2012 (rats, adapting Kalueff and Berridge): pauses **over 5 s** separate bouts; pauses up to 5 s make a bout "interrupted" [V].
  - Minkowicz et al. 2023 (automated, C57BL/6J): gaps **under 3 s** are merged and bouts **under 2 s** are discarded [V].

  **Recommendation**: make the threshold a parameter, default 5 s, and report the value used. If you adopt 6 s, check it against Kalueff & Tuohimaa 2004 (Brain Res Protoc 13:151) first.

### D2. Standard measures and observation
- **Measures**: latency to first groom; total grooming time (s); number of bouts; mean bout duration; % incorrect transitions; % interrupted bouts; % incomplete bouts; regional distribution (% of time per region).
- **Observation conditions**:
  - The common autism-model assay scores cumulative self-grooming over a **10-min** session in a clean, empty cage [V, Silverman et al. 2010 figure legend]. The habituation that usually precedes it (often 10 min) was not verified [U].
  - Kalueff's protocols use novelty-induced (spontaneous) grooming and water-spray (artificial) grooming [V, Kalueff & Tuohimaa 2004 Brain Res].
  - In rats, a 5-min session "appears to be too short" [V, Estanislau 2012].
  - Berridge 2005 used 30-min sessions [V].

### D3. Numbers
- **Face-grooming stroke rate**: Phase I has 5–10 strokes in about 1 s, so about **5–10 Hz** (*derived* from Berridge 2005). No directly measured mouse Hz value was found [U].
- **C57BL/6J baseline** (side view, 125 fps, Minkowicz 2023) [V]:
  - Grooming took up 4.1 ± 0.3% of the session. That is about 25 s per 10 min (*derived*).
  - Mean bout 12.4 ± 0.4 s.
  - Inter-bout interval 4.3 ± 0.1 min.
- Grooming amount depends heavily on context: novelty, stress, time of day and arena. Set baselines from your own C57BL/6 controls.
- 129S1/SvImJ grooms less than C57BL/6, with more interrupted and incomplete bouts and more non-cephalocaudal transitions [V, Kalueff & Tuohimaa 2004 Brain Res].

### D4. Confounds
- Stress and novelty raise the share of interrupted and incorrect grooming. Anxiolytics and anxiogenics shift it in opposite directions [V].
- Water spray, time of day, strain and sex.
- In itch and pain models, scratching and injected-paw licking contaminate grooming counts. Scratching is part of the grooming repertoire [V, Kalueff 2016]. Paw licking must be separated from pain licking (as LUPE does).
- **Bottom view**: Phases 1–3 appear as both forepaws converging on the nose/mouth keypoints and oscillating. Body licking needs the head to turn toward the flank. Tail/genital grooming puts the mouth near the tail base. Face detail is partly hidden.

### D5. Key references
1. Kalueff AV, Tuohimaa P (2004). Grooming analysis algorithm for neurobehavioural stress research. *Brain Res Protoc* 13(3):151–158. DOI 10.1016/j.brainresprot.2004.04.002. [V]
2. Kalueff AV, Tuohimaa P (2005). Mouse grooming microstructure is a reliable anxiety marker bidirectionally sensitive to GABAergic drugs. *Eur J Pharmacol* 508(1–3):147–153. DOI 10.1016/j.ejphar.2004.11.054. [V]
3. Kalueff AV, Aldridge JW, LaPorte JL, Murphy DL, Tuohimaa P (2007). Analyzing grooming microstructure in neurobehavioral experiments. *Nat Protoc* 2(10):2538–2544. DOI 10.1038/nprot.2007.367. [V]
4. Smolinsky AN, Bergner CL, LaPorte JL, Kalueff AV (2009). Analysis of grooming behavior and its utility in studying animal stress, anxiety, and depression. In: *Mood and Anxiety Related Phenotypes in Mice*, Neuromethods 42:21–36. Humana Press. DOI 10.1007/978-1-60761-303-9_2. [V]
5. Kalueff AV, Stewart AM, Song C, Berridge KC, Graybiel AM, Fentress JC (2016). Neurobiology of rodent self-grooming and its value for translational neuroscience. *Nat Rev Neurosci* 17(1):45–59. DOI 10.1038/nrn.2015.8. [V]
6. Berridge KC, Aldridge JW, Houchard KR, Zhuang X (2005). Sequential super-stereotypy of an instinctive fixed action pattern in hyper-dopaminergic mutant mice: a model of obsessive compulsive disorder and Tourette's. *BMC Biol* 3:4. DOI 10.1186/1741-7007-3-4. [V]

Also useful:
- Kalueff AV, Tuohimaa P (2004). Contrasting grooming phenotypes in C57Bl/6 and 129S1/SvImJ mice. *Brain Res* 1028(1):75–82. DOI 10.1016/j.brainres.2004.09.001. [V]
- Minkowicz S et al. (2023). Striatal ensemble activity in an innate naturalistic behavior. *eLife* 12:RP87042. DOI 10.7554/eLife.87042.1. [V]
- Silverman JL, Tolu SS, Barkan CL, Crawley JN (2010). *Neuropsychopharmacology* 35(4):976–989. DOI 10.1038/npp.2009.201. [V for journal, volume, pages and DOI; authors U]

---

## E. Default parameters for RodentLimb (summary)

| Behaviour | Default | Basis |
|---|---|---|
| Itch: bout | Hind-paw lift → rhythmic strokes at the site → ends when the paw returns to the floor, or on licking/biting of the toes, or on a pause | Valtcheva 2015 / Scratch-AID |
| Itch: merge gap | 2 s between trains | Scratch-AID consensus |
| Itch: minimum | 3 or more strokes (only if stroke-resolved, i.e. 60 fps) | MicroAct |
| Itch: stroke band | About 20 Hz (aliases to about 10 Hz at 30 fps) | Elliott 2017 |
| Itch: session / bins | 30 min, 5-min bins (20-min option) | Multiple |
| Seizure: scale | Van Erum 2019 (−1 to 7) for PTZ; Schauwecker & Steward 1997 (1–6) or Racine for kainate and pilocarpine | as cited |
| Seizure: loss of righting | All paws off the floor for more than 1 s | Copping 2021 |
| Seizure: clonus endpoint | Rhythmic limb clonus lasting at least 3–5 s | NINDS s.c. PTZ |
| Seizure: session | 30 min for PTZ (45 min option); 2–4 h or more for kainate and pilocarpine | NINDS / Ferraro / Schauwecker |
| Pain: licking | Mouth or nose touching the injected hind paw, as cumulative seconds | Wotton 2020 |
| Pain: phases | Phase I 0–10 min; Phase II 10–60 min (user-settable: 0–5 / 20–40, 0–5 / 15–45) | Mogil 1999 / Hunskaar & Hole 1987 |
| Pain: bins / session | 5-min bins, 60 min (LUPE-style: 1-min bins, 30 min) | Mogil / Wotton / LUPE |
| Pain: C57BL/6J reference | Phase I about 75 s; Phase II about 457 s (5%, 25 µl); capsaicin 2.5 µg about 106 s | MPD / Mogil 1999 |
| Grooming: session | 10 min of cumulative self-grooming | Silverman 2010 |
| Grooming: bout gap | Pause over 5 s ends a bout; shorter pauses count as interruptions (parameter; the "6 s" value is unverified) | Estanislau 2012; Kalueff (unverified) |
| Grooming: microstructure | % incorrect transitions, % interrupted bouts, % incomplete bouts, regional distribution | Kalueff & Tuohimaa 2004/2005 |
| Grooming: face-stroke band | About 5–10 Hz (Phase I) | Derived from Berridge 2005 |
