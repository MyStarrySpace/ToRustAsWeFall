# Design, Behavior & Animation References

Visual and behavioral references for translating real biology into game enemies.
All links freely viewable unless noted. Scientific images mostly public domain/CC.

---

## Movement & Behavior

### Responder (Neutrophil) — Swarming & Pursuit

- [David Rogers' Neutrophil Chase (1950s)](http://biochemweb.fenteany.com/neutrophil.shtml) — Classic 16mm film: single neutrophil stalks S. aureus through red blood cells, showing chemotaxis pursuit with visible contraction waves.
- [Pioneer neutrophils release chromatin within in vivo swarms (eLife 2021)](https://elifesciences.org/articles/68755) — Open-access. Time-lapse of neutrophil swarming in zebrafish wounds. One "pioneer" recruits waves of followers. Directly maps to Responder alert-to-swarm escalation.
- [3D Imaging Reveals Secrets of Immune Cell Agility (UCSF)](https://www.ucsf.edu/news/2017/09/408571/3-d-imaging-reveals-secrets-immune-cells-agility) — How neutrophils move faster and more nimbly than almost any other cell.

### Amoeba — Phagocytosis & Engulfment

- [Amoeba eating Paramecium (YouTube)](https://video.link/w/mv6Ehv06mXY) — Real microscopy of pseudopod extension, surrounding, engulfment. The slow inevitable mechanic.
- [Amoeba Eating Human Cells Alive (Mental Floss)](https://www.mentalfloss.com/article/56320/caught-camera-amoeba-eating-human-cells-alive) — Confocal microscopy of E. histolytica tearing pieces off living cells (trogocytosis). More aggressive attack variant.

### Naturalizer (NK Cell) — Serial Killing

- [Body's Serial Killers Captured on Film (Cambridge)](https://www.cam.ac.uk/research/news/bodys-serial-killers-captured-on-film-destroying-cancer-cells) — Time-lapse of cytotoxic cells methodically killing cancer cells then moving to next target. Clinical, serial behavior.
- [Serial Killing of Tumor Cells by NK Cells (PLOS ONE)](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0000326) — Open-access. Individual NK cells make serial contacts, lyse average of four targets each.
- [NK Cell Killing Synapse (Imperial College)](https://www.imperial.ac.uk/news/101926/cancer-killing-cells-caught-film-more-3d/) — Highest-res 3D imaging of the ring of proteins through which killing granules are delivered. Surgical precision.
- [Functional Visualization of NK Cell-Mediated Killing (eLife)](https://elifesciences.org/articles/76269) — Open-access. Lattice light sheet microscopy of NK cells hunting metastatic tumor cells.

### Sentinel (Mast Cell) — Directional Degranulation

- [Label-Free Live Imaging of Mast Cell Degranulation (Nanolive)](https://www.nanolive.com/mast-cell-degranulation/) — 3D holotomographic video: membrane ruffling, granule fusion, movement to exocytosis sites, explosive release.
- [Video-Rate Bioluminescence Imaging of Degranulation (Frontiers)](https://www.frontiersin.org/articles/10.3389/fcell.2018.00074/full) — Open-access. Video-rate detection from single mast cells. Shows directional burst pattern.

### Infiltrator (Biofilm) — Colonization & Spread

- [Time-Lapse of Bacterial Culture Patterns (SciTechDaily)](https://scitechdaily.com/stunning-time-lapse-video-shows-surprising-beauty-found-in-bacterial-cultures/) — Mixed species forming intricate flower-like patterns over 24h. Emergent, organic spread.
- [B. subtilis Biofilm Formation over 7 Days (Scientific Reports)](https://www.nature.com/articles/s41598-022-24431-y) — Open-access with supplementary time-lapse. Phases: initial colonization, wrinkle formation, ring expansion.
- [Pseudomonas Biofilm Mushroom Structure (Nature Microbiology)](https://microbiologycommunity.nature.com/posts/44446-time-lapse-imaging-of-a-pseudomonas-sp-biofilm-undergoing-restructuration-into-a-mushroom-structre) — Biofilm building vertical architecture. Infiltrator colonization visual.
- [National Biofilm Innovation Centre Image Gallery](https://biofilms.ac.uk/biofilm-image-gallery/) — Curated gallery of biofilm microscopy.

### Seeker (Complement/MAC) — Sequential Assembly

- [Single-Molecule Kinetics of MAC Pore Assembly (Nature Comms)](https://www.nature.com/articles/s41467-019-10058-7) — Open-access. Sequential C5b-C6-C7-C8-C9 recruitment at single-molecule resolution. The "split-washer" pore shape.
- [CryoEM: How MAC Ruptures Lipid Bilayers (Nature Comms)](https://www.nature.com/articles/s41467-018-07653-5) — Open-access. C6/C7 bend the membrane, C8/C9 punch through. The projectile insertion.
- [The Complement System Made Easy (LabXchange/Harvard)](https://www.labxchange.org/library/items/lb:LabXchange:37f6124f:video:1) — Free video covering all three pathways and MAC assembly.

### Night Hunter (BBB Breakdown) — Peripheral Immune Infiltration

- [BBB Immune Cell Transmigration Pathways (R&D Systems)](https://www.rndsystems.com/pathways/blood-brain-barrier-immune-cell-transmigration-pathways-overview) — Interactive diagram: rolling, activation, adhesion, locomotion, protrusion, transmigration.
- [BBB Breakdown in Alzheimer Disease (Nature Reviews Neurology)](https://www.nature.com/articles/nrneurol.2017.188) — Figures showing BBB permeability visualization in neurodegeneration.
- [High-Res Confocal Imaging of BBB (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5755420/) — Open-access. Immunofluorescence of BBB subcellular structures.

---

## Creature Design (Games/Film)

### Ecosystem & AI Design

- [Rain World Animation Process (GDC)](https://www.gdcvault.com/play/1023475/Animation-Bootcamp-Rainworld-Animation) — Free GDC talk. Procedural animation where creatures have limbs and decide how to use them, not pre-baked animations.
- [Crafting the Complex, Chaotic Ecosystem of Rain World (Game Developer)](https://www.gamedeveloper.com/design/crafting-the-complex-chaotic-ecosystem-of-i-rain-world-i-) — AI ecosystem where creatures hunt, fight, behave autonomously even off-screen. Model for enemies that exist independently of the player.
- [Animating Rain World's Squishy, Stretchy Creatures (Game Developer)](https://www.gamedeveloper.com/art/video-animating-i-rain-world-i-and-its-many-squishy-stretchy-creatures) — Point-based procedural animation for organic, non-robotic movement.
- [Hollow Knight Enemies and Real-Life Creatures (The Gamer)](https://www.thegamer.com/hollow-knight-enemies-real-life-creatures-based-on/) — How biological accuracy enhances design believability.

### Chain Enemy — Segmented Locomotion

- [Procedural Animation Tutorial (WeaverDev)](https://weaverdev.io/projects/proc-anim-tutorial/) — Free, MIT-licensed source. IK-based follow-the-leader chain movement with skinned model.
- [Procedural Creature Progress 2021-2024 (Rune Vision)](https://blog.runevision.com/2025/01/procedural-creature-progress-2021-2024.html) — Multi-year devlog from basic IK to complex multi-limbed movement.
- [Procedural Locomotion Part 1 (Little Polygon)](https://blog.littlepolygon.com/posts/loco1/) — Foot-placement-and-step-trigger system for chain segments.

### Gnawer Enemy — Arthropod Movement

- [Ultimate Centipede Locomotion (Fab/Unreal)](https://www.fab.com/listings/4f3e8478-5e0f-4b3f-942c-823e8f9ec9af) — Procedural centipede with legs that individually determine foot placement. Study the approach.
- [Embodied Approach to Arthropod Animation (Cenydd 2013)](https://onlinelibrary.wiley.com/doi/abs/10.1002/cav.1436) — Decentralized reactive locomotion: autonomous wall climbing, rigid-body interaction, emergent behaviors.
- [Procedural Centipede & Bug (itch.io)](https://humensmoc.itch.io/procedural-anim) — Playable Unity tech demo. Run in browser to see how procedural leg placement feels.

### Sentinel Enemy — Turret/Sniper Patterns

- [Enemy NPC Design Patterns in Shooter Games (Academia.edu)](https://www.academia.edu/2806378/Enemy_NPC_Design_Patterns_in_Shooter_Games) — Academic paper cataloging enemy archetypes. Turret units force tactical play, slow pace.
- [Design Patterns in FPS Levels (Hullett & Whitehead)](https://users.soe.ucsc.edu/~ejw/papers/hullett-fps-fdg2010.pdf) — How turret/sniper placement interacts with level design, forcing alternate routes.
- [Keys to Rational Enemy Design (GDKeys)](https://gdkeys.com/keys-to-rational-enemy-design/) — Framework for designing enemies by gameplay role.

---

## Image Databases (Public Domain / CC)

- [NIAID Flickr](https://www.flickr.com/photos/niaid/) — All public domain. Colorized SEM of NK cells, T cells, bacteria, biofilms.
- [NIH BioArt Source](https://bioart.niaid.nih.gov/) — 2000+ professional medical illustrations (SVG/PNG/AI/EPS), free, no login. Bacteria, cells, cellular processes.
- [The Inner Life of the Cell (Harvard/XVIVO)](https://xvivo.com/examples/the-inner-life-of-the-cell/) — Landmark 2006 animation showing molecular machinery inside a white blood cell. Gold standard for translating cellular processes into visual storytelling.
- [Innate Immune System Animation (XVIVO)](https://xvivo.com/examples/the-innate-immune-system/) — Multiple immune cell types coordinating response.
- [Neutrophil-Biofilm Interactions SEM (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10764082/) — Open-access. Neutrophils embedded in 3D architecture of P. aeruginosa biofilms.
