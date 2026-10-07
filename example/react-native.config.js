// @rnmapbox/maps is here for MapModelLayer over another library's Mapbox map,
// which is Android only (on iOS, MapModelLayer draws over MapKit maps). Its
// iOS pod pins a Mapbox version that munim-maps' own Mapbox engine does not
// share, so the iOS app leaves it out.
module.exports = {
  dependencies: {
    '@rnmapbox/maps': {
      platforms: {
        ios: null,
      },
    },
  },
}
