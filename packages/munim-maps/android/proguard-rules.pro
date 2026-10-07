# munim-maps finds its map engines by class name (MunimMapEngines), so keep
# them; MapModelLayer's adapters for other libraries' map views
# (MapViewAdapters) are found the same way, in the same packages.
-keep class com.munimmaps.engines.** { *; }
-keep class com.munimmaps.engine.MunimMapEngineFactory { *; }
# Nitro hybrid objects and views are created from C++.
-keep class com.margelo.nitro.munimmaps.** { *; }
