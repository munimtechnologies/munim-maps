package com.margelo.nitro.munimmaps

import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.facebook.react.uimanager.ThemedReactContext
import com.margelo.nitro.core.Promise
import com.munimmaps.engine.MapViewAdapters
import com.munimmaps.models.MunimModelLayer

/**
 * React Native `MapModelLayer` on Android: munim-maps' 3D layer over another
 * library's map. It looks for the map (the view whose `testID` is
 * `mapTestID`, or the nearest map up the hierarchy) through
 * [MapViewAdapters], which engines fill with adapters for their SDK's view
 * (react-native-maps' Google `MapView` comes with the Google engine). Until
 * one matches, it reports `onAttachChange(false)`.
 */
class HybridMapModelLayer(context: ThemedReactContext) : HybridMapModelLayerSpec() {
  private val layer = MunimModelLayer(context)
  private val frame = object : FrameLayout(context) {
    override fun onAttachedToWindow() {
      super.onAttachedToWindow()
      search()
    }

    override fun onDetachedFromWindow() {
      super.onDetachedFromWindow()
      handler.removeCallbacks(searchLater)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
      super.onLayout(changed, l, t, r, b)
      layer.view.layout(0, 0, r - l, b - t)
      layer.setNeedsRender()
    }
  }
  private val handler = Handler(Looper.getMainLooper())
  private val searchLater = Runnable { search() }
  private var reportedAttached: Boolean? = null
  private var searches = 0

  override val view: View get() = frame

  init {
    frame.addView(layer.view, FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    layer.onModelPress = { id -> onModelPress?.invoke(id) }
    layer.onError = { message -> onError?.invoke(message) }
  }

  private fun search() {
    if (!frame.isAttachedToWindow) return
    val source = findMap()
    if (source != null) {
      layer.attach(source)
      report(true)
      return
    }
    report(false)
    searches += 1
    if (searches == 20) {
      onError?.invoke(
        "MapModelLayer found no map it can draw over on Android. Use MunimMapView, or the engine " +
          "for your map library (react-native-maps needs the Google engine).")
    }
    handler.postDelayed(searchLater, if (searches < 20) 250L else 2000L)
  }

  private fun findMap() = if (mapTestID.isNotEmpty()) {
    findTagged(frame.rootView)?.let { MapViewAdapters.find(it, skip = frame) }
  } else {
    var ancestor = frame.parent as? View
    var found: com.munimmaps.engine.MapCameraSource? = null
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
      layer.detach()
      searches = 0
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
