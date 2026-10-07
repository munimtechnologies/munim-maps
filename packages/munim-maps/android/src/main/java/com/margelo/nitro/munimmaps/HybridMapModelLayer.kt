package com.margelo.nitro.munimmaps

import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import com.facebook.react.uimanager.ThemedReactContext
import com.margelo.nitro.core.Promise
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapViewAdapters
import com.munimmaps.models.MunimModelLayer

/**
 * React Native `MapModelLayer` on Android: munim-maps' 3D layer over another
 * library's map. It looks for the map (the view whose `testID` is
 * `mapTestID`, or the nearest map up the hierarchy) through
 * [MapViewAdapters]: react-native-maps' Google `MapView` and
 * `@rnmapbox/maps`' Mapbox `MapView`, whose adapters are compiled whenever
 * those libraries are in the app. Until one matches, it reports
 * `onAttachChange(false)`.
 *
 * The 3D layer's view is kept exactly over the map's view (position and
 * size, before every draw), so the layer can be anywhere around the map.
 */
class HybridMapModelLayer(context: ThemedReactContext) : HybridMapModelLayerSpec() {
  private val layer = MunimModelLayer(context)
  private val frame = object : FrameLayout(context) {
    override fun onAttachedToWindow() {
      super.onAttachedToWindow()
      viewTreeObserver.addOnPreDrawListener(followMap)
      search()
    }

    override fun onDetachedFromWindow() {
      super.onDetachedFromWindow()
      viewTreeObserver.removeOnPreDrawListener(followMap)
      handler.removeCallbacks(searchLater)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
      super.onLayout(changed, l, t, r, b)
      placeOverMap()
      layer.setNeedsRender()
    }
  }
  private val handler = Handler(Looper.getMainLooper())
  private val searchLater = Runnable { search() }
  private var reportedAttached: Boolean? = null
  private var searches = 0
  private var source: MapCameraSource? = null
  private val frameLocation = IntArray(2)
  private val mapLocation = IntArray(2)

  /** Before every draw: follow the map's view, and look again when it has gone. */
  private val followMap = ViewTreeObserver.OnPreDrawListener {
    if (source != null && source?.cameraView == null) {
      // The map left the window (a new screen, a remount): find it again.
      detachSource()
      searches = 0
      handler.removeCallbacks(searchLater)
      handler.post(searchLater)
    } else {
      placeOverMap()
    }
    true
  }

  override val view: View get() = frame

  init {
    frame.addView(layer.view, FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    layer.onModelPress = { id -> onModelPress?.invoke(id) }
    layer.onError = { message -> onError?.invoke(message) }
  }

  /** Lays the 3D layer's view out over the map's view (in the frame's coordinates). */
  private fun placeOverMap() {
    val map = source?.cameraView
    val target = layer.view
    var left = 0
    var top = 0
    var width = frame.width
    var height = frame.height
    if (map != null && map.width > 0 && map.height > 0) {
      frame.getLocationInWindow(frameLocation)
      map.getLocationInWindow(mapLocation)
      left = mapLocation[0] - frameLocation[0]
      top = mapLocation[1] - frameLocation[1]
      width = map.width
      height = map.height
    }
    if (target.left != left || target.top != top || target.width != width || target.height != height) {
      target.layout(left, top, left + width, top + height)
      layer.setNeedsRender()
    }
  }

  private fun search() {
    if (!frame.isAttachedToWindow) return
    val found = findMapView()
    if (found != null) {
      source = found
      layer.attach(found)
      found.setTapListener { x, y -> layer.handleTap(x, y) }
      placeOverMap()
      report(true)
      return
    }
    report(false)
    searches += 1
    if (searches == 20) {
      onError?.invoke(
        if (MapViewAdapters.isEmpty) {
          "MapModelLayer: no map library munim-maps can draw over is built into this app. On Android it " +
            "draws over react-native-maps and @rnmapbox/maps; or use MunimMapView."
        } else {
          "MapModelLayer found no map it can draw over. Give the map a testID and pass it as mapTestID, " +
            "or put the layer next to a react-native-maps or @rnmapbox/maps MapView."
        })
    }
    handler.postDelayed(searchLater, if (searches < 20) 250L else 2000L)
  }

  private fun detachSource() {
    source?.setTapListener(null)
    source = null
    layer.detach()
    report(false)
  }

  private fun findMapView(): MapCameraSource? = if (mapTestID.isNotEmpty()) {
    findTagged(frame.rootView)?.let { MapViewAdapters.find(it, skip = frame) }
  } else {
    var ancestor = frame.parent as? View
    var found: MapCameraSource? = null
    var depth = 0
    while (ancestor != null && found == null && depth < 10) {
      found = MapViewAdapters.find(ancestor, skip = frame)
      ancestor = ancestor.parent as? View
      depth += 1
    }
    found
  }

  private fun findTagged(view: View): View? {
    if (view.getTag(com.facebook.react.R.id.react_test_id) == mapTestID) return view
    if (view is ViewGroup) {
      for (i in 0 until view.childCount) findTagged(view.getChildAt(i))?.let { return it }
    }
    return null
  }

  private fun report(attached: Boolean) {
    if (reportedAttached == attached) return
    reportedAttached = attached
    onAttachChange?.invoke(attached)
  }

  override fun onDropView() {
    handler.removeCallbacks(searchLater)
    source?.setTapListener(null)
    source = null
    layer.destroy()
  }

  override var models: Array<NativeMapModel> = emptyArray()
    set(value) { field = value; layer.models = value }
  override var zones: Array<NativeMapZone> = emptyArray()
    set(value) { field = value; layer.zones = value }
  override var paths: Array<NativeMapPath> = emptyArray()
    set(value) { field = value; layer.paths = value }
  override var occlusion: MapOcclusion = MapOcclusion.NONE
    set(value) { field = value; layer.buildingOcclusion = value == MapOcclusion.BUILDINGS }
  override var buildingTilesUrl: String = ""
    set(value) { field = value; layer.buildingTilesUrl = value }
  override var followTerrain: Boolean = false
    set(value) { field = value; layer.followsTerrain = value }
  override var mapTestID: String = ""
    set(value) {
      if (field == value) return
      field = value
      detachSource()
      searches = 0
      handler.removeCallbacks(searchLater)
      search()
    }
  override var lighting: MapModelLighting = MapModelLighting.AUTO
    set(value) { field = value; layer.lighting = value }
  override var maxCameraDistance: Double = 50_000.0
    set(value) { field = value; layer.maxCameraDistance = value }
  /** MapKit only. */
  override var realisticElevation: Boolean = false
  /** MapKit only. */
  override var globe: Boolean = false
  override var onModelPress: ((id: String) -> Unit)? = null
  override var onAttachChange: ((attached: Boolean) -> Unit)? = null
  override var onError: ((message: String) -> Unit)? = null

  override fun isAttached(): Boolean = layer.isAttached

  override fun measureAlignment(): Promise<MapAlignmentReport> {
    val promise = Promise<MapAlignmentReport>()
    handler.post { promise.resolve(layer.measureAlignment()) }
    return promise
  }
}
