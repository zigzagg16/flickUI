# Webcams: ideas for later

## Vehicle speed (parked: too inaccurate on the current pictures)

Live stream only; the still pictures are a minute apart.

1. **Relative to the speed limit.** Map each camera's learned peak movement to the
   limit (about 110 km/h). No setup, but crude: near and far traffic are mixed.
2. **Per-camera calibration.** Tap four points on the lane markings; lane width
   (about 3.5 m) and the dash pattern give a homography from picture to road. Store
   it per camera in the catalog. Speed per vehicle = optical flow inside its
   detection box, converted to metres, over the frame gap; median per carriageway.
   Check Luxembourg's motorway dash length and spacing first.
3. **Automatic calibration** from the vanishing point and lane width: research-level.

Expected accuracy ±15–20 % at best; low resolution, compression, night and rain make
it worse. Show averages per carriageway only, never per vehicle.

## Other ideas

- Favourites and a "my route" view: an ordered list of cameras for a commute.
- Alerts when a favourite camera turns jammed or shows snow (background refresh).
- Siri and Shortcuts: "How's the A13?", building on the widget's camera entity.
- Live Activity for a jam on the route.
- Timelapse of the last hour per camera.
- cita.lu truck parking, from its DATEX II parking feeds.
- Map of the cameras (coordinates in the catalog).
- Apple Watch complication, CarPlay status.
- History per camera: "busier than usual" against past reports at that hour.
- Feed the live stream's frames, per camera label, into the vehicle and weather
  analysis, and link live cameras to catalog cameras by their caption.
