// Expo config plugin for munim-maps: chooses the map engines built into the
// app and writes their keys into the native config.
//
//   ["munim-maps", {
//     "providers": ["google", "maplibre"],        // engines besides MapKit (iOS) / MapLibre (Android)
//     "ios": { "providers": ["mapbox"] },           // per platform, added to `providers`
//     "android": { "providers": ["cesium"] },
//     "googleMapsApiKey": "…" | { "ios": "…", "android": "…" },
//     "mapboxAccessToken": "pk.…",
//     "cesiumIonToken": "…",
//     "cesium": { "bundled": true },               // CesiumJS in the app (13 MB) instead of from jsDelivr
//     "maplibre": { "bundledWeb": true },          // MapLibre GL JS + three.js in the app instead of from jsDelivr
//     "googleMaps3d": true                         // Google's photorealistic 3D SDK (iOS and Android)
//   }]
//
// iOS: Podfile.properties.json `munimMaps.providers` (the podspec turns
// those subspecs on) and `munimMaps.googleMaps3d`, Info.plist `MunimMapsGoogleMapsApiKey`,
// `MBXAccessToken`, `MunimMapsCesiumIonToken`.
// Android: gradle.properties `munimMaps.<provider>=true`, manifest
// `com.google.android.geo.API_KEY` and `munimmaps.cesium_ion_token`
// meta-data, and the `mapbox_access_token` string resource.
let plugins
try {
  plugins = require('expo/config-plugins')
} catch {
  plugins = require('@expo/config-plugins')
}
const {
  AndroidConfig,
  withAndroidManifest,
  withGradleProperties,
  withInfoPlist,
  withPodfileProperties,
  withProjectBuildGradle,
  withStringsXml,
  withXcodeProject,
} = plugins

const MAPBOX_MAVEN = 'https://api.mapbox.com/downloads/v2/releases/maven'

/**
 * Adds Mapbox's Maven repository (public, no secret token) to the app's
 * `allprojects.repositories`: the app resolves the Mapbox SDK that comes
 * through munim-maps.
 */
function addMapboxMaven(gradle) {
  if (gradle.includes(MAPBOX_MAVEN)) return gradle
  const line = `    maven { url '${MAPBOX_MAVEN}' }\n`
  const match = /allprojects\s*\{\s*repositories\s*\{[^\n]*\n/.exec(gradle)
  if (match) {
    const at = match.index + match[0].length
    return gradle.slice(0, at) + line + gradle.slice(at)
  }
  return `${gradle}\nallprojects {\n  repositories {\n${line}  }\n}\n`
}

const PROVIDERS = ['mapkit', 'google', 'mapbox', 'maplibre', 'cesium']

function list(value, where) {
  if (value == null) return []
  if (!Array.isArray(value)) {
    throw new TypeError(`munim-maps: ${where} must be an array of providers`)
  }
  for (const provider of value) {
    if (!PROVIDERS.includes(provider)) {
      throw new TypeError(
        `munim-maps: unknown provider "${provider}" in ${where} (${PROVIDERS.join(', ')})`
      )
    }
  }
  return value
}

function providersFor(options, platform) {
  const all = [
    ...list(options.providers, 'providers'),
    ...list(options[platform]?.providers, `${platform}.providers`),
  ]
  // MapKit is always there on iOS and does not exist on Android.
  return [...new Set(all)].filter((p) => p !== 'mapkit')
}

/** `cesium: { bundled: true }`: CesiumJS in the app instead of from jsDelivr. */
function cesiumBundled(options, providers) {
  return providers.includes('cesium') && options.cesium?.bundled === true
}

/**
 * `maplibre: { bundledWeb: true }`: MapLibre GL JS (the `maplibre`
 * provider's web renderer) and three.js in the app instead of from jsDelivr.
 * MapLibre is on by default on Android and opt-in on iOS.
 */
function maplibreBundled(options, providers, platform) {
  const on = platform === 'android' || providers.includes('maplibre')
  return on && options.maplibre?.bundledWeb === true
}

function keyFor(value, platform) {
  if (value == null) return undefined
  if (typeof value === 'string') return value
  return value[platform]
}

function setMetaData(application, name, value) {
  if (value) {
    AndroidConfig.Manifest.addMetaDataItemToMainApplication(
      application,
      name,
      value
    )
  } else {
    AndroidConfig.Manifest.removeMetaDataItemFromMainApplication(
      application,
      name
    )
  }
}

function withMunimMapsIos(config, options) {
  const providers = providersFor(options, 'ios')
  config = withPodfileProperties(config, (c) => {
    if (providers.length > 0) {
      c.modResults['munimMaps.providers'] = providers.join(',')
    } else {
      delete c.modResults['munimMaps.providers']
    }
    if (cesiumBundled(options, providers)) {
      c.modResults['munimMaps.cesiumBundled'] = 'true'
    } else {
      delete c.modResults['munimMaps.cesiumBundled']
    }
    if (maplibreBundled(options, providers, 'ios')) {
      c.modResults['munimMaps.maplibreBundled'] = 'true'
    } else {
      delete c.modResults['munimMaps.maplibreBundled']
    }
    // Google's photorealistic 3D map: the NitroMunimMaps/Google3D subspec,
    // which adds Google's GoogleMaps3D Swift package to the pod.
    if (options.googleMaps3d && providers.includes('google')) {
      c.modResults['munimMaps.googleMaps3d'] = 'true'
    } else {
      delete c.modResults['munimMaps.googleMaps3d']
    }
    return c
  })
  config = withInfoPlist(config, (c) => {
    const entries = {
      MunimMapsGoogleMapsApiKey: keyFor(options.googleMapsApiKey, 'ios'),
      MBXAccessToken: options.mapboxAccessToken,
      MunimMapsCesiumIonToken: options.cesiumIonToken,
    }
    for (const [key, value] of Object.entries(entries)) {
      if (value) c.modResults[key] = value
    }
    return c
  })
  return config
}

function withMunimMapsAndroid(config, options) {
  const providers = providersFor(options, 'android')
  config = withGradleProperties(config, (c) => {
    const props = c.modResults
    for (const provider of PROVIDERS.filter((p) => p !== 'mapkit')) {
      const key = `munimMaps.${provider}`
      const index = props.findIndex(
        (item) => item.type === 'property' && item.key === key
      )
      if (index >= 0) props.splice(index, 1)
      if (providers.includes(provider)) {
        props.push({ type: 'property', key, value: 'true' })
      }
    }
    // Google's photorealistic 3D map SDK (google={{ mode: '3d' }}).
    const index3d = props.findIndex(
      (item) =>
        item.type === 'property' && item.key === 'munimMaps.googleMaps3d'
    )
    if (index3d >= 0) props.splice(index3d, 1)
    if (options.googleMaps3d && providers.includes('google')) {
      props.push({
        type: 'property',
        key: 'munimMaps.googleMaps3d',
        value: 'true',
      })
    }
    // CesiumJS in the APK (cesium: { bundled: true }).
    const indexCesium = props.findIndex(
      (item) =>
        item.type === 'property' && item.key === 'munimMaps.cesiumBundled'
    )
    if (indexCesium >= 0) props.splice(indexCesium, 1)
    if (cesiumBundled(options, providers)) {
      props.push({
        type: 'property',
        key: 'munimMaps.cesiumBundled',
        value: 'true',
      })
    }
    // MapLibre GL JS and three.js in the APK (maplibre: { bundledWeb: true }).
    const indexMapLibre = props.findIndex(
      (item) =>
        item.type === 'property' && item.key === 'munimMaps.maplibreBundled'
    )
    if (indexMapLibre >= 0) props.splice(indexMapLibre, 1)
    if (maplibreBundled(options, providers, 'android')) {
      props.push({
        type: 'property',
        key: 'munimMaps.maplibreBundled',
        value: 'true',
      })
    }
    return c
  })
  config = withAndroidManifest(config, (c) => {
    const application = AndroidConfig.Manifest.getMainApplicationOrThrow(
      c.modResults
    )
    setMetaData(
      application,
      'com.google.android.geo.API_KEY',
      keyFor(options.googleMapsApiKey, 'android')
    )
    setMetaData(
      application,
      'munimmaps.cesium_ion_token',
      options.cesiumIonToken
    )
    return c
  })
  if (providers.includes('mapbox')) {
    config = withProjectBuildGradle(config, (c) => {
      if (c.modResults.language === 'groovy') {
        c.modResults.contents = addMapboxMaven(c.modResults.contents)
      }
      return c
    })
  }
  if (options.mapboxAccessToken) {
    config = withStringsXml(config, (c) => {
      c.modResults = AndroidConfig.Strings.setStringItem(
        [
          AndroidConfig.Resources.buildResourceItem({
            name: 'mapbox_access_token',
            value: options.mapboxAccessToken,
            translatable: false,
          }),
        ],
        c.modResults
      )
      return c
    })
  }
  return config
}

/**
 * Bundling CesiumJS copies it from the app's own `cesium` package at build
 * time (munim-maps does not ship it): say so at prebuild when that package
 * is missing or not the version the engine is written for.
 */
function checkBundledCesium(config, options) {
  const bundled = ['ios', 'android'].some((platform) =>
    cesiumBundled(options, providersFor(options, platform))
  )
  if (!bundled) return
  const {
    resolveCesium,
    versionWarning,
  } = require('./scripts/cesium/copy-cesium')
  try {
    const warning = versionWarning(
      resolveCesium({ root: config._internal?.projectRoot ?? process.cwd() })
    )
    if (warning) console.warn(`munim-maps: ${warning}`)
  } catch (error) {
    console.warn(`munim-maps: ${error.message}`)
  }
}

/** The same for bundled MapLibre GL JS (the app's `maplibre-gl` and `three`). */
function checkBundledMapLibre(config, options) {
  const bundled = ['ios', 'android'].some((platform) =>
    maplibreBundled(options, providersFor(options, platform), platform)
  )
  if (!bundled) return
  const {
    resolvePackages,
    warnings,
  } = require('./scripts/maplibre/copy-maplibre-web')
  try {
    const found = resolvePackages({
      root: config._internal?.projectRoot ?? process.cwd(),
    })
    for (const warning of warnings(found))
      console.warn(`munim-maps: ${warning}`)
  } catch (error) {
    console.warn(`munim-maps: ${error.message}`)
  }
}

const GOOGLE_MAPS_3D_PACKAGE = 'https://github.com/googlemaps/ios-maps-3d-sdk'
// Pinned like the Android SDK; MUNIM_MAPS_GOOGLE_MAPS_3D_VERSION (at prebuild
// and `pod install`) overrides it in both places.
const GOOGLE_MAPS_3D_VERSION =
  process.env.MUNIM_MAPS_GOOGLE_MAPS_3D_VERSION || '1.0.0'
const GOOGLE_MAPS_3D_PRODUCT = 'GoogleMaps3D'

/**
 * Adds Google's `GoogleMaps3D` Swift package to the app target, so Xcode
 * embeds its dynamic framework in the app. The pod compiles against the
 * same package (React Native's `spm_dependency`, in NitroMunimMaps.podspec),
 * but a package product linked by a static-library pod is only linked into
 * the app, not embedded: without this the app stops at launch with
 * `Library not loaded: @rpath/GoogleMaps3D.framework/GoogleMaps3D`.
 * Idempotent; `project` is the `xcode` package's project.
 */
function addGoogleMaps3dPackage(project, version = GOOGLE_MAPS_3D_VERSION) {
  const objects = project.hash.project.objects
  const section = (name) => (objects[name] = objects[name] ?? {})
  const entries = (name) =>
    Object.entries(section(name)).filter(([key]) => !key.endsWith('_comment'))
  const unquote = (value) => String(value ?? '').replace(/^"(.*)"$/, '$1')
  const packageComment = 'XCRemoteSwiftPackageReference "ios-maps-3d-sdk"'

  let packageId = entries('XCRemoteSwiftPackageReference').find(
    ([, value]) => unquote(value.repositoryURL) === GOOGLE_MAPS_3D_PACKAGE
  )?.[0]
  if (!packageId) {
    packageId = project.generateUuid()
    section('XCRemoteSwiftPackageReference')[packageId] = {
      isa: 'XCRemoteSwiftPackageReference',
      repositoryURL: `"${GOOGLE_MAPS_3D_PACKAGE}"`,
      requirement: { kind: 'exactVersion', version },
    }
    section('XCRemoteSwiftPackageReference')[`${packageId}_comment`] =
      packageComment
  } else {
    section('XCRemoteSwiftPackageReference')[packageId].requirement = {
      kind: 'exactVersion',
      version,
    }
  }
  const root = objects.PBXProject[project.hash.project.rootObject]
  root.packageReferences = root.packageReferences ?? []
  if (!root.packageReferences.some((ref) => ref.value === packageId)) {
    root.packageReferences.push({ value: packageId, comment: packageComment })
  }

  const app = entries('PBXNativeTarget').find(
    ([, value]) =>
      unquote(value.productType) === 'com.apple.product-type.application'
  )
  if (!app) throw new Error('munim-maps: no app target in the Xcode project')
  const [targetId, target] = app

  let productId = entries('XCSwiftPackageProductDependency').find(
    ([, value]) =>
      value.package === packageId &&
      unquote(value.productName) === GOOGLE_MAPS_3D_PRODUCT
  )?.[0]
  if (!productId) {
    productId = project.generateUuid()
    section('XCSwiftPackageProductDependency')[productId] = {
      isa: 'XCSwiftPackageProductDependency',
      package: packageId,
      package_comment: packageComment,
      productName: GOOGLE_MAPS_3D_PRODUCT,
    }
    section('XCSwiftPackageProductDependency')[`${productId}_comment`] =
      GOOGLE_MAPS_3D_PRODUCT
  }
  target.packageProductDependencies = target.packageProductDependencies ?? []
  if (
    !target.packageProductDependencies.some((ref) => ref.value === productId)
  ) {
    target.packageProductDependencies.push({
      value: productId,
      comment: GOOGLE_MAPS_3D_PRODUCT,
    })
  }

  const frameworks = project.pbxFrameworksBuildPhaseObj(targetId)
  if (!frameworks)
    throw new Error('munim-maps: the app target has no Frameworks build phase')
  const linked = frameworks.files.some((file) => {
    const buildFile = section('PBXBuildFile')[file.value]
    return buildFile && buildFile.productRef === productId
  })
  if (!linked) {
    const buildFileId = project.generateUuid()
    section('PBXBuildFile')[buildFileId] = {
      isa: 'PBXBuildFile',
      productRef: productId,
      productRef_comment: GOOGLE_MAPS_3D_PRODUCT,
    }
    section('PBXBuildFile')[`${buildFileId}_comment`] =
      `${GOOGLE_MAPS_3D_PRODUCT} in Frameworks`
    frameworks.files.push({
      value: buildFileId,
      comment: `${GOOGLE_MAPS_3D_PRODUCT} in Frameworks`,
    })
  }
  return project
}

/** Removes what `addGoogleMaps3dPackage` added (the 3D map turned off). */
function removeGoogleMaps3dPackage(project) {
  const objects = project.hash.project.objects
  const unquote = (value) => String(value ?? '').replace(/^"(.*)"$/, '$1')
  const packages = objects.XCRemoteSwiftPackageReference ?? {}
  const packageIds = Object.keys(packages).filter(
    (key) =>
      !key.endsWith('_comment') &&
      unquote(packages[key].repositoryURL) === GOOGLE_MAPS_3D_PACKAGE
  )
  if (packageIds.length === 0) return project
  const products = objects.XCSwiftPackageProductDependency ?? {}
  const productIds = Object.keys(products).filter(
    (key) =>
      !key.endsWith('_comment') && packageIds.includes(products[key].package)
  )
  const buildFiles = objects.PBXBuildFile ?? {}
  const buildFileIds = Object.keys(buildFiles).filter(
    (key) =>
      !key.endsWith('_comment') &&
      productIds.includes(buildFiles[key].productRef)
  )
  const drop = (table, ids) => {
    for (const id of ids) {
      delete table[id]
      delete table[`${id}_comment`]
    }
  }
  drop(packages, packageIds)
  drop(products, productIds)
  drop(buildFiles, buildFileIds)
  for (const [key, value] of Object.entries(objects.PBXProject ?? {})) {
    if (key.endsWith('_comment') || !value.packageReferences) continue
    value.packageReferences = value.packageReferences.filter(
      (ref) => !packageIds.includes(ref.value)
    )
  }
  for (const [key, value] of Object.entries(objects.PBXNativeTarget ?? {})) {
    if (key.endsWith('_comment') || !value.packageProductDependencies) continue
    value.packageProductDependencies = value.packageProductDependencies.filter(
      (ref) => !productIds.includes(ref.value)
    )
  }
  for (const [key, value] of Object.entries(
    objects.PBXFrameworksBuildPhase ?? {}
  )) {
    if (key.endsWith('_comment') || !value.files) continue
    value.files = value.files.filter(
      (file) => !buildFileIds.includes(file.value)
    )
  }
  return project
}

function withGoogleMaps3dPackage(config, options) {
  const enabled =
    options.googleMaps3d && providersFor(options, 'ios').includes('google')
  return withXcodeProject(config, (c) => {
    if (enabled) addGoogleMaps3dPackage(c.modResults)
    else removeGoogleMaps3dPackage(c.modResults)
    return c
  })
}

module.exports = function withMunimMaps(config, options = {}) {
  checkBundledCesium(config, options)
  checkBundledMapLibre(config, options)
  config = withMunimMapsIos(config, options)
  config = withGoogleMaps3dPackage(config, options)
  config = withMunimMapsAndroid(config, options)
  return config
}

module.exports.addMapboxMaven = addMapboxMaven
module.exports.addGoogleMaps3dPackage = addGoogleMaps3dPackage
module.exports.removeGoogleMaps3dPackage = removeGoogleMaps3dPackage
