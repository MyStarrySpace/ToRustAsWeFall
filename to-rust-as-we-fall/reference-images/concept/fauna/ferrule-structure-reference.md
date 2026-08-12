# Ferrule — Pyoverdine Structure Reference

## Important qualification

“Pyoverdine” names a family of related siderophores, not one universal molecule.
Members share:

- a fluorescent dihydroxyquinoline chromophore;
- a strain-specific peptide scaffold, which may be linear or partly cyclic;
- a variable acyl side chain.

For reproducible visual development, use **Pyoverdine I (ChEBI 80048)** as the
primary molecular reference unless another strain-specific variant is named.

## Primary 2D references

- [ChEBI: Pyoverdine I (CHEBI:80048)](https://www.ebi.ac.uk/chebi/searchId.do?chebiId=CHEBI%3A80048)
  — curated structure, formula, stereochemical SMILES, and identifiers.
- [Wikimedia Commons: Pyoverdine.svg](https://commons.wikimedia.org/wiki/File:Pyoverdine.svg)
  — clean public-domain 2D structure drawing.
- [Pyoverdine type-I component diagram](https://www.mdpi.com/1422-0067/23/19/11507)
  — visually separates the chromophore, peptide backbone, and acyl side chain.
- [PAO1 pyoverdine structure diagram](https://www.mdpi.com/1422-0067/22/4/2211)
  — labels the chromophore and peptide residues.

## Experimental 3D references

- [RCSB PDB 1XKH](https://www.rcsb.org/structure/1XKH)
  — FpvA receptor with iron-free pyoverdine.
- [RCSB PDB 2W78](https://www.rcsb.org/structure/2W78)
  — FpvA receptor with a ferripyoverdine complex.
- [RCSB PDB 2IAH](https://www.rcsb.org/structure/2IAH)
  — another ferripyoverdine-bound receptor structure.

These structures show experimentally resolved bound conformations, not a single
free-floating “default pose” for every member of the pyoverdine family.

## Pyoverdine I identifiers

- ChEBI: `CHEBI:80048`
- Formula: `C55H83N17O22`
- InChIKey: `CVWNSOHSMMCZJU-YYVBLSOISA-N`

### Isomeric SMILES

```text
[H][C@@]1([C@@H](C)O)NC(=O)[C@H](CCCN(O)C=O)NC(=O)[C@@H](NC(=O)[C@H](CCCN(O)C=O)NC(=O)[C@@H](CO)NC(=O)[C@H](CCCNC(=N)N)NC(=O)[C@@H](CO)NC(=O)[C@@H]2CCN=C3C(NC(=O)CCC(=O)O)=Cc4cc(O)c(O)cc4N32)CCCCNC(=O)[C@]([H])([C@@H](C)O)NC1=O
```

SMILES records molecular connectivity and stereochemistry; it is not a model
sheet or a unique 3D pose. Use the PDB structures above when conformation matters.

## Visual-design implications for Ferrule

- The chromophore should read as a **compact interlocking fused-ring wedge**, not
  an enormous detached diamond or shovel head.
- The peptide scaffold is a major part of the molecule. It can become a short
  sequence of low-poly, interlocking body masses that folds back toward the head.
- Iron capture is distributed across the molecule. Show two inward-facing
  chelation structures on the peptide loop working with the chromophore, rather
  than putting the entire capture function in the head.
- This supports an asymmetrical, off-center silhouette distinct from Sapscrap’s
  compact threefold enterobactin cage.
- Pyoverdine fluorescence is quenched by iron binding. Ferrule can therefore be
  brighter while searching and visibly dimmer after securing iron, making state
  legible without adding anatomy.

## Art-direction shorthand

**Compact fused-ring head + abbreviated peptide loop + three inward capture
points; angular, low-poly, low-resolution, and readable at fodder-enemy scale.**
