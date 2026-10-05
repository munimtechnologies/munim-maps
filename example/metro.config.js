// Learn more: https://docs.expo.dev/guides/customizing-metro/
const { getDefaultConfig } = require('expo/metro-config')

const config = getDefaultConfig(__dirname)

// Bundle 3D models so the example can pass them to munim-maps with require().
config.resolver.assetExts.push('usdz')

module.exports = config
