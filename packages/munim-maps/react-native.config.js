// https://github.com/react-native-community/cli/blob/main/docs/dependencies.md

module.exports = {
  dependency: {
    platforms: {
      /**
       * @type {import('@react-native-community/cli-types').IOSDependencyParams}
       */
      ios: {},
      // iOS only for now: Android apps can use Mapbox's built-in model layer.
      android: null,
    },
  },
}
