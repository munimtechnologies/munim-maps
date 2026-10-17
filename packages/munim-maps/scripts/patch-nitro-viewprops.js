/**
 * Works around margelo/nitro#1656: on Android, a Nitro Hybrid View receives no
 * base ViewProps (opacity, backgroundColor, transform, testID, accessibility…)
 * when React Native no longer fills `Props::rawProps` from the base
 * constructor. Android serialises exactly that map to Java, so an empty map
 * means `BaseViewManager` never sees a single style prop.
 *
 * - React Native >= 0.87 removed the call from `Props::initialize`.
 * - React Native 0.84–0.86 skip it when the
 *   `enableExclusivePropsUpdateAndroid` feature flag is on.
 *
 * Mirrors the upstream fix (margelo/nitro PR #1661, still unreleased as of
 * Nitro 0.37.1): call `initializeDynamicProps` from the generated
 * `Hybrid*Props` constructor in exactly those two cases, so it never runs twice.
 *
 * Run after `nitrogen` (see the `codegen` script). Fails if an anchor in the
 * generated code has drifted, so a Nitro upgrade cannot silently drop the fix.
 * Delete this script once a Nitro release that contains PR #1661 is adopted.
 */
const path = require('node:path')
const fs = require('node:fs')

const MARKER = 'munim-maps: margelo/nitro#1656'
const viewsDir = path.join(
  __dirname,
  '..',
  'nitrogen/generated/shared/c++/views'
)

// Nitro 0.37 includes ViewProps.h from the header, so anchor on the .cpp's
// own ReactProp include.
const includeAnchor = '#include <NitroModules/ReactProp.hpp>\n'
const includeBlock = `${includeAnchor}
// ${MARKER} (see scripts/patch-nitro-viewprops.js)
#ifdef ANDROID
#if __has_include(<cxxreact/ReactNativeVersion.h>)
#include <cxxreact/ReactNativeVersion.h>
#endif
#if defined(REACT_NATIVE_VERSION_MINOR) && REACT_NATIVE_VERSION_MAJOR == 0 && REACT_NATIVE_VERSION_MINOR >= 84 && REACT_NATIVE_VERSION_MINOR < 87
#include <react/featureflags/ReactNativeFeatureFlags.h>
#endif
#endif
`

// The props constructor's initializer list ends right before the generated
// `filterObjectKeys` definition: `...sourceProps.last)) { }\n\n  bool XProps::filterObjectKeys`.
const ctorEndAnchor = /\)\) \{ \}\n\n( {2}bool (\w+)::filterObjectKeys\()/g
const ctorBody = `)) {
    // ${MARKER}: React Native no longer fills Props::rawProps for us.
#if defined(ANDROID) && defined(RN_SERIALIZABLE_STATE) && defined(REACT_NATIVE_VERSION_MINOR)
#if REACT_NATIVE_VERSION_MAJOR > 0 || REACT_NATIVE_VERSION_MINOR >= 87
    initializeDynamicProps(sourceProps, rawProps, filterObjectKeys);
#elif REACT_NATIVE_VERSION_MINOR >= 84
    if (facebook::react::ReactNativeFeatureFlags::enableExclusivePropsUpdateAndroid()) {
      initializeDynamicProps(sourceProps, rawProps, filterObjectKeys);
    }
#endif
#endif
  }

`

function fail(message) {
  throw new Error(`patch-nitro-viewprops: ${message}`)
}

const files = fs
  .readdirSync(viewsDir)
  .filter((name) => name.endsWith('Component.cpp'))
if (files.length === 0) fail(`no *Component.cpp files in ${viewsDir}`)

let patched = 0
for (const file of files) {
  const filePath = path.join(viewsDir, file)
  const original = fs.readFileSync(filePath, 'utf8')
  if (original.includes(MARKER)) {
    // Already patched (codegen was not re-run). Still verify both halves.
    if (!original.includes('initializeDynamicProps(sourceProps, rawProps')) {
      fail(`${file} carries the marker but not the constructor call`)
    }
    continue
  }

  if (original.split(includeAnchor).length !== 2) {
    fail(`${file}: expected exactly one "${includeAnchor.trim()}" anchor`)
  }
  let source = original.replace(includeAnchor, includeBlock)

  const ctorMatches = [...source.matchAll(ctorEndAnchor)]
  if (ctorMatches.length !== 1) {
    fail(
      `${file}: expected exactly one props constructor ending in ")) { }" ` +
        `before ::filterObjectKeys, found ${ctorMatches.length}. ` +
        `Nitrogen's output changed — re-check margelo/nitro#1656 / PR #1661.`
    )
  }
  if (
    !/^\s+react::ViewProps\(context, sourceProps, rawProps, filterObjectKeys\)/m.test(
      source
    )
  ) {
    fail(
      `${file}: props no longer forward filterObjectKeys to react::ViewProps`
    )
  }
  source = source.replace(ctorEndAnchor, (_, tail) => `${ctorBody}${tail}`)

  fs.writeFileSync(filePath, source)
  patched++
}

console.log(
  `patch-nitro-viewprops: patched ${patched} of ${files.length} hybrid view props`
)
