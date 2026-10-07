package com.munimmaps.engines.google

import android.graphics.Point
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import org.json.JSONArray
import org.json.JSONObject

// Methods only Google has, from JavaScript's `providerCommand` (typed in
// `googleMap(ref)`).

private fun cameraJson(p: CameraPosition) = GOut.obj(
  "latitude" to p.target.latitude, "longitude" to p.target.longitude, "zoom" to p.zoom.toDouble(),
  "bearing" to p.bearing.toDouble(), "tilt" to p.tilt.toDouble(),
)

internal fun GoogleMapEngine.runCommand(command: String, args: GJson, completion: (Result<String>) -> Unit) {
  fun done(value: Any? = null) = completion(Result.success(when (value) {
    null -> "null"
    is JSONObject, is JSONArray -> value.toString()
    is String -> JSONObject.quote(value)
    else -> value.toString()
  }))
  fun fail(message: String) = completion(Result.failure(IllegalStateException("Google Maps: $message")))

  if (command.startsWith("streetView.")) return streetViewCommand(command.removePrefix("streetView."), args, ::done, ::fail)
  if (command == "sdkInfo") {
    val version = runCatching {
      context.packageManager.getPackageInfo("com.google.android.gms", 0).versionName
    }.getOrNull() ?: ""
    return done(GOut.obj("platform" to "android", "version" to version, "renderer" to "latest",
      "openSourceLicenseInfo" to ""))
  }
  val map = map ?: return fail("the map is not ready yet")
  val duration = args["duration"].double(0.0)
  when (command) {
    "getCameraPosition" -> done(cameraJson(map.cameraPosition))
    "moveCamera", "animateCamera" -> {
      val current = map.cameraPosition
      val position = CameraPosition.Builder(current)
        .target(args.latLng ?: current.target)
        .zoom(args["zoom"].double(current.zoom.toDouble()).toFloat())
        .bearing(args["bearing"].double(current.bearing.toDouble()).toFloat())
        .tilt(args["tilt"].double(current.tilt.toDouble()).toFloat())
        .build()
      stopFlight()
      val update = CameraUpdateFactory.newCameraPosition(position)
      when {
        command == "moveCamera" -> map.moveCamera(update)
        duration > 0 -> map.animateCamera(update, duration.toInt(), null)
        else -> map.animateCamera(update)
      }
      modelLayer.setNeedsRender()
      done()
    }
    "zoomIn" -> { move(CameraUpdateFactory.zoomIn(), duration); done() }
    "zoomOut" -> { move(CameraUpdateFactory.zoomOut(), duration); done() }
    "zoomTo" -> { move(CameraUpdateFactory.zoomTo(args["zoom"].double(map.cameraPosition.zoom.toDouble()).toFloat()), duration); done() }
    "zoomBy" -> {
      val amount = args["amount"].double(1.0).toFloat()
      val x = args["x"].double
      val y = args["y"].double
      val update = if (x != null && y != null) CameraUpdateFactory.zoomBy(amount, Point((x * density).toInt(), (y * density).toInt()))
      else CameraUpdateFactory.zoomBy(amount)
      move(update, duration)
      done()
    }
    "scrollBy" -> {
      move(CameraUpdateFactory.scrollBy((args["x"].double(0.0) * density).toFloat(), (args["y"].double(0.0) * density).toFloat()), duration)
      done()
    }
    "fitBounds" -> {
      val bounds = args.bounds ?: return fail("fitBounds needs southwest and northeast")
      val p = args["padding"]
      val pad = (p.double ?: listOf(p["top"].double(0.0), p["left"].double(0.0), p["bottom"].double(0.0), p["right"].double(0.0)).max()) * density
      move(CameraUpdateFactory.newLatLngBounds(bounds, pad.toInt()), duration)
      done()
    }
    "stopAnimation" -> {
      stopFlight()
      map.stopAnimation()
      done()
    }
    "getProjection" -> {
      val region = map.projection.visibleRegion
      done(GOut.obj(
        "nearLeft" to GOut.latLng(region.nearLeft), "nearRight" to GOut.latLng(region.nearRight),
        "farLeft" to GOut.latLng(region.farLeft), "farRight" to GOut.latLng(region.farRight),
        "bounds" to GOut.bounds(region.latLngBounds), "camera" to cameraJson(map.cameraPosition),
        "pointsPerMeter" to 1 / (metersPerPixel() * density),
      ))
    }
    "pointsForMeters" -> {
      val at = args.latLng ?: map.cameraPosition.target
      val perMeter = GoogleCamera.pixelsPerMeter(map.cameraPosition.zoom.toDouble(), at.latitude, density) / density
      done(args["meters"].double(1.0) * perMeter)
    }
    "containsCoordinate" -> {
      val c = args.latLng ?: return fail("containsCoordinate needs latitude and longitude")
      done(map.projection.visibleRegion.latLngBounds.contains(c))
    }
    "getMapCapabilities" -> {
      val c = map.mapCapabilities
      done(GOut.obj("advancedMarkers" to c.isAdvancedMarkersAvailable, "dataDrivenStyling" to c.isDataDrivenStylingAvailable))
    }
    "getMyLocation" -> {
      @Suppress("DEPRECATION")
      val l = runCatching { map.myLocation }.getOrNull() ?: return done()
      done(GOut.obj("latitude" to l.latitude, "longitude" to l.longitude, "altitude" to l.altitude,
        "accuracy" to l.accuracy.toDouble(), "heading" to l.bearing.toDouble(), "speed" to l.speed.toDouble()))
    }
    "getIndoorBuilding" -> done(indoorBuilding())
    "setIndoorLevel" -> {
      val building = map.focusedBuilding ?: return fail("no indoor building is focused")
      val index = args["index"].double(-1.0).toInt()
      val level = building.levels.getOrNull(index)
        ?: building.levels.firstOrNull { it.shortName == args["shortName"].string || it.name == args["name"].string }
        ?: return fail("no such level")
      level.activate()
      done()
    }
    "showInfoWindow" -> { selectMarkerById(args["id"].string ?: ""); done() }
    "hideInfoWindow" -> { deselectMarkerById(args["id"].string ?: ""); done() }
    "clearTileCache" -> { clearTileCache(args["id"].string); done() }
    "cameraDiagnostics" -> {
      val view = mapView ?: return fail("no map view")
      val state = GoogleCamera.state(map, view, paddingPx(), density, false)
      val p = map.cameraPosition
      done(GOut.obj(
        "fieldOfViewDegrees" to GoogleCamera.fieldOfView * 180 / Math.PI,
        "fieldOfViewMeasured" to GoogleCamera.fieldOfViewMeasured,
        "distance" to (state?.distance ?: -1.0),
        "distanceFromZoom" to GoogleCamera.distance(p.zoom.toDouble(), p.target.latitude, view.height.toDouble(), density),
        "focalLength" to (state?.focalLength ?: -1.0),
        "camera" to cameraJson(p),
        "centerX" to (state?.centerX ?: -1.0) / density, "centerY" to (state?.centerY ?: -1.0) / density,
        "width" to view.width / density, "height" to view.height / density,
      ))
    }
    else -> fail("unknown command \"$command\"")
  }
}

private fun GoogleMapEngine.streetViewCommand(command: String, args: GJson, done: (Any?) -> Unit, fail: (String) -> Unit) {
  when (command) {
    "open" -> openStreetView(args) { result -> result.fold({ done(it) }, { fail(it.message ?: "no Street View here") }) }
    "close" -> { closeStreetView(); done(null) }
    "hasCoverage" -> streetViewCoverage(args) { done(it) }
    else -> {
      val street = streetView ?: return fail("Street View is not open")
      when (command) {
        "setCamera" -> { street.setCamera(args, args["duration"].double(0.0).toLong()); done(null) }
        "getCamera" -> done(street.cameraInfo)
        "getLocation" -> done(street.locationInfo)
        "moveTo" -> {
          val pano = street.panorama ?: return fail("Street View is still loading")
          val id = args["panoramaId"].string
          val position = args.latLng
          when {
            id != null -> pano.setPosition(id)
            position != null -> pano.setPosition(position, args["radius"].double(50.0).toInt(),
              if (args["source"].string == "outdoor") com.google.android.gms.maps.model.StreetViewSource.OUTDOOR
              else com.google.android.gms.maps.model.StreetViewSource.DEFAULT)
            else -> return fail("moveTo needs latitude and longitude, or panoramaId")
          }
          done(null)
        }
        "setOptions" -> { street.apply(args); done(null) }
        "orientationForPoint" -> done(street.orientationForPoint(args["x"].double(0.0), args["y"].double(0.0)))
        "pointForOrientation" -> done(street.pointForOrientation(args["heading"].double(0.0), args["pitch"].double(0.0)))
        else -> fail("unknown command \"streetView.$command\"")
      }
    }
  }
}
