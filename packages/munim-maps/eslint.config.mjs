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
  {
    // No Flow here, and eslint-plugin-ft-flow 2 (React Native's) still
    // calls ESLint 8's context.getAllComments.
    rules: {
      'ft-flow/define-flow-type': 'off',
      'ft-flow/use-flow-type': 'off',
    },
  },
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
