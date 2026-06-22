# DetectorOSC

iOS app that detects objects (YOLOv8) from the camera or a video file and streams the results over OSC.

## OSC Output Format

All messages for one video frame are sent together in a single OSC bundle.
Coordinates are normalized (0.0–1.0) with the origin at the **top-left** of the
image as shown on the device screen — orientation (portrait/landscape) and
camera (back/front) are compensated automatically, so the OSC values always
match what you see in the app's preview.

### Per-frame count

```
/<label>/count <int: n>
```

Example: `/person/count 3` — three people are currently detected.
When a label disappears entirely, `count 0` is sent once so receivers can reset.

### Per-object position (with stable tracking ID)

One value per address, so receivers get self-describing channel names
(e.g. TouchDesigner's OSC In CHOP shows them as `person/2/x`, `person/2/y`, …):

```
/<label>/<id>/x          <float>
/<label>/<id>/y          <float>
/<label>/<id>/w          <float>
/<label>/<id>/h          <float>
/<label>/<id>/confidence <float>
```

Example:

```
/person/2/x 0.41
/person/2/y 0.22
/person/2/w 0.18
/person/2/h 0.55
/person/2/confidence 0.87
```

- `id` is assigned per label starting from 1 and stays stable while the object
  remains in view (simple frame-to-frame tracking; an object that disappears
  for more than ~1 second frees its ID for reuse).
- `x`, `y` are the top-left corner of the bounding box; the four corners are
  `(x, y)`, `(x+w, y)`, `(x, y+h)`, `(x+w, y+h)`,
  and the center is `(x + w/2, y + h/2)`.

### Max/MSP

Requires the [odot](https://github.com/CNMAT/CNMAT-odot) package
(install via Max Package Manager).

Two example patches are included in this repository:

| File | Description |
|------|-------------|
| `example_osc_monitor.maxpat` | Displays raw OSC values (x, y, w, h, confidence) for person 1. Useful for debugging and verifying the data stream. |
| `example_visualizer.maxpat` | Draws color-coded bounding boxes for multiple people on an `lcd` object. Requires `detectorosc_draw.js` in the same folder. |

#### Routing basics

```
[udpreceive 8000]
|
[OSC-route /person]
|
[OSC-route /count /1 /2 /3 /4]
                   |
                   [OSC-route /x /y /w /h /confidence]
```

`/person/count 2` → after `[OSC-route /person]` → `/count 2` →
`[OSC-route /count /1 /2 /3 /4]` matches `/count` and outputs `2`.

`/person/1/x 0.5` → after `[OSC-route /person]` → `/1/x 0.5` →
matches `/1` → `/x 0.5` → matches `/x` → outputs `0.5`.

Change `/person` to any label the model detects (e.g. `/car`, `/dog`).

<img width="1246" height="688" alt="example_osc_monitor" src="https://github.com/user-attachments/assets/c3bce564-cf81-4740-ac0d-89715ac5d09e" />

<img width="1372" height="955" alt="example_visualizer" src="https://github.com/user-attachments/assets/0e2194f4-b42e-461f-a67b-43bea63a8259" />
