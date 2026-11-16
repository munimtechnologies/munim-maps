// ESLint 9 flat config: React Native's rules, with Prettier formatting as
// warnings (the `prettier` settings in package.json).
import reactNative from '@react-native/eslint-config/flat'
import prettierRecommended from 'eslint-plugin-prettier/recommended'

export default [
  {
    ignores: [
      'node_modules/',
      'lib/',
      'nitrogen/generated/',
      'vehicles.js',
      'vehicles-glb.js',
      'cesium/',
      'maplibre/',
      'android/build/',
    ],
  },
  ...reactNative,
  prettierRecommended,
  {
    rules: {
      'prettier/prettier': [
        'warn',
        {
          quoteProps: 'consistent',
          singleQuote: true,
          tabWidth: 2,
          trailingComma: 'es5',
          useTabs: false,
        },
      ],
    },
  },
]
