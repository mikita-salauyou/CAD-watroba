# KWOD CAD Wątroba — prototyp

Prototyp systemu CAD do **objętościowej oceny wątroby i zmian ogniskowych
w badaniach CT** (zgodnie z koncepcją projektu `KWOD_koncepcja.pdf`).

Projekt składa się z jednej części (manual-only):

| Folder    | Język  | Cel                                  |
|----------|--------|---------------------------------------|
| `matlab/` | MATLAB | Aplikacja desktopowa (manual segment) |

## Część MATLAB — aplikacja kliniczna

Funkcje:

- wczytanie badania CT (folder DICOM/IRCAD),
- **manualna segmentacja** (gold standard) — freehand na kilku przekrojach + interpolacja signed-distance transform,
- obliczanie objętości wątroby/zmian i udziału procentowego,
- narzędzia CAD: **linijka** (mm) i **kolista ROI** (cm² + statystyki HU: średnia, σ, min, max),
- analiza jakości: porównanie z **maskami referencyjnymi IRCAD** — Dice + różnica objętości.

### Uruchomienie

Wymagania: MATLAB R2022b+, Image Processing Toolbox.

```matlab
cd('C:\New project\CAD watroba\matlab');
clear classes
main
```

`clear classes` jest potrzebne raz po pobraniu nowej wersji (MATLAB cache'uje
`classdef`).

### Workflow

| Pasek 1 (input + segmentacja)                                                  |
|--------------------------------------------------------------------------------|
| `Open DICOM Folder...`                                                        |
| `Manual liver`, `Manual lesion` — freehand, puszczenie myszy kończy            |
| `Interpolate` — uzupełnia brakujące przekroje między klatkami kluczowymi       |
| `Clear masks` — reset                                                          |
| status + WL 60 / WW 180 (preset wątrobowy, niezmienny)                         |

| Pasek 2 (review)                                                                |
|--------------------------------------------------------------------------------|
| `Show liver / lesions / ref` — niezależne włączanie nakładek                   |
| `Ruler`, `Circle ROI`, `Clear measures`                                        |
| `Load reference (IRCAD)` — folder `MASKS_DICOM` → Dice w panelu Metrics        |

Slice-label pokazuje `*L` / `*E` na przekrojach oznaczonych jako klatki kluczowe.

### Architektura

Szczegóły techniczne: `matlab/ARCHITECTURE.md`.

## Dane wejściowe

- **DICOM folder** — folder z plikami `.dcm` jednej serii CT (np. IRCAD
  `PATIENT_DICOM/`); aplikacja sama wchodzi w typowe wrappery
  (`PATIENT_DICOM`, `DICOM`, `IMAGES`).
- **MASKS_DICOM** (IRCAD) — opcjonalna referencja jakości w MATLAB UI
  (Dice / objętości).
