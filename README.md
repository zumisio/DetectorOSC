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

### Legacy format (kept for backward compatibility)

```
/<label> <string: label> <float: confidence>
```

Example: `/person person 0.87`

### Max/MSP example

```
[udpreceive 8000]
|
[route /person]
|
[route count 1 2 3 4]
        |
        [route x y w h confidence]
```

`/person/count` arrives as `count <n>` after `[route /person]`, and
`/person/1/x …` arrives as `1 x <float>`, so a second `[route 1 2 3 4]`
followed by `[route x y w h confidence]` splits it per person and per value.
