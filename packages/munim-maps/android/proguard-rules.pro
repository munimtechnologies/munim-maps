# munim-maps finds its map engines by class name (MunimMapEngines), so keep them.
-keep class com.munimmaps.engines.** { *; }
-keep class com.munimmaps.engine.MunimMapEngineFactory { *; }
# Nitro hybrid objects and views are created from C++.
-keep class com.margelo.nitro.munimmaps.** { *; }
