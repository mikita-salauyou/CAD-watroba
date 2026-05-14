# MATLAB CAD Architecture

## Goal (per project concept `KWOD_koncepcja.pdf`)

Prototype CAD system for CT liver analysis:

1. Load a CT study (NIfTI file **or** DICOM folder).
2. **Three segmentation modes**, all interoperable on the same masks:
   - **Semi-automatic seeded region growing** — single click,
     fast (a few seconds for the whole 3D volume).
   - **Fully manual polygon contouring** per slice (gold-standard
     workflow). User draws on every Nth slice; the missing slices are
     filled by signed-distance-transform interpolation between
     keyframes.
   - **Mixed**: seed first to get a rough mask, refine problem slices
     manually.
3. Compute liver volume, lesion volume, lesion percentage of the liver.
4. CAD review tools — linear measurements (rulers in mm) and circular
   ROIs with area in cm² and HU statistics (mean, std, min, max).
5. Quality analysis — load IRCAD ground-truth masks (`MASKS_DICOM`)
   and compute Dice + volume difference vs. the user segmentation.
6. Visualize axial slices with mask overlays, reference contours and
   measurements, plus a metrics panel.

Automation / ML pipeline removed (manual-only).

## Modules

- `main.m` — entry point; instantiates and shows `KWODApp`.
- `KWODApp.m` — desktop UI (`uifigure` + `uigridlayout`). Two toolbars:
  - Top: `Open DICOM Folder...`,
         `Manual liver`, `Manual lesion`, `Interpolate`,
         `Clear masks`, status, fixed WL/WW label.
  - Tools: `Show liver`, `Show lesions`, `Show ref` checkboxes,
           `Ruler`, `Circle ROI`, `Clear measures`,
           `Load reference (IRCAD)`.
  - Side panel: slice slider, +/- slice step buttons, legend.
  - Metrics panel: volumes, keyframes per organ, Dice vs reference,
    measurement list.
  - Slice label shows `*L` / `*E` markers on slices that are manual
    keyframes for liver / lesion respectively.
- (Removed) NIfTI loading — manual-only DICOM workflow.
- `+kwod/loadDicomStudy.m` — loads a DICOM CT series; squeezes
  `dicomreadVolume` 4D output to 3D, drills into common subfolders
  (`PATIENT_DICOM`, `DICOM`, `IMAGES`), reconstructs spacing.
- `+kwod/loadReferenceMasks.m` — loads IRCAD `MASKS_DICOM` ground truth.
  - Drills into nested `MASKS_DICOM/` if needed.
  - Subfolder `liver/` → `ref.liver`.
  - Subfolders matching `livertumor*` / `livercyst*` / `tumor*` /
    `metastasis*` → union into `ref.lesion`.
  - Skips other organs (`bone`, `kidney`, `portalvein`, etc.).
Seed-based segmentation modules removed (manual-only workflow).
     so the lesion cannot touch the liver border (subcapsular vessels,
     edge artefacts, segmentation imperfections cause false growth
     otherwise). Falls back gracefully if the seed lies near the edge.
  3. **HU band**: `seedVal ± 25 HU`, intersected with the inner liver.
  4. **26-connected `imreconstruct`** from the seed.
  5. **Cleanup**: in-plane opening (1 × 3 × 3), drop components below
     30 voxels, intersect with the original (uneroded) liver mask for
     strict containment.
- `+kwod/interpolateKeyframes.m` — fill missing slices between manually
  drawn keyframes via **signed-distance-transform** interpolation
  (positive inside, negative outside; linear blend, threshold at 0).
  Standard medical-imaging trick: produces smooth, anatomically
  plausible transitions; degenerates gracefully when one keyframe is
  empty.
- `+kwod/computeVolumes.m` — voxel counts → cm³, lesion percent of liver.
- `+kwod/dice.m` — Sørensen–Dice between two binary masks.
- `+kwod/measureLine.m` — physical length of a 2D line in mm using
  in-plane spacing.
- `+kwod/measureCircle.m` — area in cm², equivalent diameter in mm
  and HU statistics inside a 2D circular ROI.

## Study data model

```
study.volumeZYX     : single [Z, Y, X], HU
study.shapeZYX      : [Z, Y, X]
study.spacingXYZmm  : [dx, dy, dz]
study.filePath      : source file or series folder
```

Masks (`MaskLiver`, `MaskLesion`, `RefLiver`, `RefLesion`)
are `logical [Z, Y, X]`.

`Measurements` is a cell array of structs of two kinds:

```
{
  struct(type="line",   slice, points (2x2),
         lengthMm, midpoint),
  struct(type="circle", slice, center, radiusPx,
         diameterMm, areaCm2, meanHU, stdHU, minHU, maxHU)
}
```

A measurement is rendered only when its `slice` matches `CurrentZ`.

## Processing flow

```
Open DICOM folder
   -> kwod.loadDicomStudy
   -> study struct stored in KWODApp

[A] Manual liver / lesion
   -> user draws slice keyframes -> Interpolate -> MaskLiver / MaskLesion
   -> merged into MaskLesion

[B] Manual liver (drawpolygon on uiaxes)
   -> 2D polygon mask written into MaskLiver(z, :, :)
   -> z added to LiverKeyframes

[B] Manual lesion (drawpolygon, intersected with MaskLiver(z,:,:))
   -> merged into MaskLesion(z, :, :)
   -> z added to LesionKeyframes

[B] Interpolate
   -> kwod.interpolateKeyframes(MaskLiver, LiverKeyframes)
   -> kwod.interpolateKeyframes(MaskLesion, LesionKeyframes)
   -> lesion clipped by liver after interpolation

Ruler   (drawline on uiaxes)
   -> kwod.measureLine(points, spacing)        -> Measurements{...type=line}

Circle ROI (drawcircle on uiaxes)
   -> kwod.measureCircle(slice, mask, center,
                         radius, spacing)       -> Measurements{...type=circle}

Load reference (IRCAD MASKS_DICOM)
   -> kwod.loadReferenceMasks(folder, shape)   -> RefLiver, RefLesion

Rendering
   -> imagesc slice with fixed WL/WW (60/180)
   -> green/red overlays (user masks, alpha)
   -> blue/pink contours (reference masks, edges only)
   -> ruler lines + length labels in mm
   -> circle ROIs + area / mean HU labels

Metrics
   -> kwod.computeVolumes(MaskLiver, MaskLesion, spacing)
   -> + Dice(MaskLiver, RefLiver), Dice(MaskLesion, RefLesion)
   -> + per-measurement lines (L1, L2, ...; C1, C2, ...)
```

## Extensibility

- Add a manual correction brush on top of the seeded masks.
- Export metrics + measurements to CSV / JSON per study.
- Add per-slice 2D Dice heatmap, Hausdorff distance.
- Replace seeded heuristic with deep-learning model
  (e.g. nnU-Net inference) while keeping the same UI and data contracts.
