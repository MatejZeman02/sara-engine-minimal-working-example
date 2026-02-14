# Ideas from before:

## Pipeline:
- cpu gdscript:
  - profiles, brush/keyboard inputs
  - undo
  - dirty area
  - non active layers?
- gpu:
  - active layer
  - canvas/viewport
  - brush dab (tah stetce)
  - compute shaders

### 3. Tok dat (Workflow)
- Input (CPU): Godot zachytí InputEventMouseMotion (tlak, pozice, tilt).
- Dispatch (CPU -> GPU): Pošleš souřadnice a parametry do Compute Shaderu.
- Compute (GPU): Shader vypočítá změnu pixelů na textuře aktivní vrstvy (zde aplikuješ svou interpolaci).
- Zobrazení (GPU): Výsledek se rovnou zobrazí. Žádné stahování dat zpět na CPU v každém snímku!
- Commit (GPU -> CPU): Až ve chvíli, kdy uživatel zvedne pero (konec tahu), stáhneš změněnou oblast (nebo jen dotčené dlaždice) z GPU do RAM a uložíš ji jako nový stav pro Undo.

## Extern libraries:
- LittleCMS (LCMS2) - ICC profiles support
- LibMyPaint - painting engine
- Eigen/GLM lin. algebra math

