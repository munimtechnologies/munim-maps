package com.munimmaps

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager
import com.margelo.nitro.munimmaps.NitroMunimMapsOnLoad
import com.margelo.nitro.munimmaps.views.HybridMapModelLayerManager
import com.margelo.nitro.munimmaps.views.HybridMarkerViewManager
import com.margelo.nitro.munimmaps.views.HybridMunimMapViewManager

class MunimMapsPackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? = null

  override fun getReactModuleInfoProvider(): ReactModuleInfoProvider = ReactModuleInfoProvider { emptyMap() }

  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> =
    listOf(HybridMunimMapViewManager(), HybridMapModelLayerManager(), HybridMarkerViewManager())

  companion object {
    init {
      NitroMunimMapsOnLoad.initializeNative()
    }
  }
}
