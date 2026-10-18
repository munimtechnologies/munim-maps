import assert from 'node:assert/strict'
import { test } from 'node:test'
import { colorOr, normalizeColor } from '../src/colors.ts'

test('hex stays hex, upper case, alpha last', () => {
  assert.equal(normalizeColor('#0a84ff'), '#0A84FF')
  assert.equal(normalizeColor('#0A84FF33'), '#0A84FF33')
  assert.equal(normalizeColor('#abc'), '#AABBCC')
  assert.equal(normalizeColor('#abcd'), '#AABBCCDD')
  assert.equal(normalizeColor('#0A84FFFF'), '#0A84FF')
})

test('rgb() and rgba(), comma and space syntax', () => {
  assert.equal(normalizeColor('rgb(10, 132, 255)'), '#0A84FF')
  assert.equal(normalizeColor('rgba(10, 132, 255, 0.2)'), '#0A84FF33')
  assert.equal(normalizeColor('rgba(255,0,0,1)'), '#FF0000')
  assert.equal(normalizeColor('rgb(255 0 0 / 50%)'), '#FF000080')
  assert.equal(normalizeColor('rgb(100%, 0%, 0%)'), '#FF0000')
  assert.equal(normalizeColor('RGBA(0, 0, 0, 0)'), '#00000000')
  assert.equal(normalizeColor('rgba(300, -5, 0, 2)'), '#FF0000')
})

test('hsl() and hsla()', () => {
  assert.equal(normalizeColor('hsl(0, 100%, 50%)'), '#FF0000')
  assert.equal(normalizeColor('hsl(120deg 100% 25%)'), '#008000')
  assert.equal(normalizeColor('hsla(240, 100%, 50%, 0.5)'), '#0000FF80')
  assert.equal(normalizeColor('hsl(0.5turn, 100%, 50%)'), '#00FFFF')
})

test('transparent and CSS names', () => {
  assert.equal(normalizeColor('transparent'), '#00000000')
  assert.equal(normalizeColor('red'), '#FF0000')
  assert.equal(normalizeColor('RebeccaPurple'), '#663399')
  assert.equal(normalizeColor(' white '), '#FFFFFF')
})

test('empty, missing and unknown values', () => {
  assert.equal(normalizeColor(undefined), '')
  assert.equal(normalizeColor(null), '')
  assert.equal(normalizeColor(''), '')
  assert.equal(normalizeColor('not-a-colour'), 'not-a-colour')
  assert.equal(normalizeColor('#12345'), '#12345')
  assert.equal(normalizeColor('rgb(1, 2)'), 'rgb(1, 2)')
})

test('colorOr falls back only when the colour is left out', () => {
  assert.equal(colorOr(undefined, '#0A84FF'), '#0A84FF')
  assert.equal(colorOr(null, '#0A84FF'), '#0A84FF')
  assert.equal(colorOr('', '#0A84FF'), '')
  assert.equal(colorOr('rgba(0,0,0,0.5)', '#0A84FF'), '#00000080')
})
