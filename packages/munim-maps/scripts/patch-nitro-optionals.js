/**
 * Works around margelo/nitro#1319: in iOS Release builds, reading an optional
 * struct or enum through Swift's `std::optional` `.value` projection can
 * return garbage (a "present" value with random enum tags) when JS passed
 * nothing. Nitrogen already routes optional numbers and booleans through the
 * bridge's `has_value_*` / `get_*` helpers; this rewrites the remaining
 * `.value` projections in the generated Swift (struct field getters, spec
 * method arguments and hybrid view prop setters) to use them too.
 *
 * Run after `nitrogen` (see the `codegen` script). Fails if a helper is missing.
 */
const path = require('node:path')
const fs = require('node:fs')

const swiftDir = path.join(__dirname, '..', 'nitrogen/generated/ios/swift')
const bridgeHeader = fs.readFileSync(
  path.join(
    __dirname,
    '..',
    'nitrogen/generated/ios/NitroMunimMaps-Swift-Cxx-Bridge.hpp'
  ),
  'utf8'
)

function checked(bridgeType, expression) {
  for (const helper of [`has_value_${bridgeType}`, `get_${bridgeType}`]) {
    if (!bridgeHeader.includes(` ${helper}(`)) {
      throw new Error(
        `patch-nitro-optionals: bridge helper ${helper} not found`
      )
    }
  }
  return `(bridge.has_value_${bridgeType}(${expression}) ? bridge.get_${bridgeType}(${expression}) : nil)`
}

let patched = 0
for (const file of fs
  .readdirSync(swiftDir)
  .filter((name) => name.endsWith('.swift'))) {
  const filePath = path.join(swiftDir, file)
  let source = fs.readFileSync(filePath, 'utf8')
  const original = source

  // Struct getters: `var name: Type? { return self.__name.value }`
  source = source.replace(
    /(var (\w+): (\w+)\? \{\n\s*return )self\.__\2\.value\n/g,
    (_, head, name, type) => {
      patched++
      return `${head}${checked(`std__optional_${type}_`, `self.__${name}`)}\n`
    }
  )

  // Spec methods: `param: bridge.std__optional_X_` unwrapped as `param.value`.
  // Parameter names repeat across methods with different types, so resolve
  // them per method.
  source = source
    .split(/(?=\n {2}@inline\(__always\)\n)/)
    .map((chunk) => {
      const signature = chunk.match(/public final func \w+\(([^)]*)\)/)
      if (!signature) return chunk
      let result = chunk
      for (const [, name, bridgeType] of signature[1].matchAll(
        /(\w+): bridge\.(std__optional_\w+?_)(?=[,)]|$)/g
      )) {
        result = result.replace(
          new RegExp(`: ${name}\\.value([,)])`, 'g'),
          (_, tail) => {
            patched++
            return `: ${checked(bridgeType, name)}${tail}`
          }
        )
      }
      return result
    })
    .join('')

  // View prop setters: `public final var name: bridge.std__optional_X_`
  // whose setter assigns `newValue.value`.
  source = source
    .split(/(?=\n {2}public final var )/)
    .map((chunk) => {
      const property = chunk.match(
        /^\n {2}public final var (\w+): bridge\.(std__optional_\w+?_) \{/
      )
      if (!property) return chunk
      const [, name, bridgeType] = property
      return chunk.replace(
        new RegExp(`(self\\.__implementation\\.${name} = )newValue\\.value\n`),
        (_, head) => {
          patched++
          return `${head}${checked(bridgeType, 'newValue')}\n`
        }
      )
    })
    .join('')

  if (source !== original) fs.writeFileSync(filePath, source)
}

const leftover = fs
  .readdirSync(swiftDir)
  .filter((name) => name.endsWith('.swift'))
  .flatMap((name) =>
    fs
      .readFileSync(path.join(swiftDir, name), 'utf8')
      .split('\n')
      .filter(
        (line) =>
          /\b\w+\.value\b(?!\()/.test(line) &&
          !/__result\.value|\.value\s*=/.test(line)
      )
      .map((line) => `${name}: ${line.trim()}`)
  )
if (leftover.length > 0) {
  throw new Error(
    `patch-nitro-optionals: unchecked .value projections remain:\n${leftover.join('\n')}`
  )
}
console.log(`patch-nitro-optionals: rewrote ${patched} optional projections`)
