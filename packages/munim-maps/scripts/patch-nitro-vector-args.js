/**
 * Nitrogen 0.36.x converts `std::vector<T>` method arguments to Swift arrays
 * with `vector.map({ __item in __item })`. With Xcode 26's Swift toolchain
 * the collection conformance for some of those instantiations is missing,
 * so the generated code does not compile ("value of type
 * 'std.vector<MapCoordinate>' has no member 'map'"). Xcode 27 compiles it,
 * which is why device builds never showed it (same issue as munim-xr's
 * patch-nitro-double-vectors.js).
 *
 * This rewrites those conversions, in hybrid method arguments and struct
 * array getters (including `[[T]]`), to explicit `size()` / subscript loops,
 * which need no conformance. Prop setters are left alone (they compile on
 * both toolchains).
 *
 * Run after `nitrogen` (see the `codegen` script). Idempotent. Fails if a
 * vector argument still uses `.map`, so a Nitro upgrade that changes the
 * generated shape cannot silently reintroduce the break.
 */
const path = require('node:path')
const fs = require('node:fs')

const swiftDir = path.join(__dirname, '..', 'nitrogen/generated/ios/swift')
const NAMESPACE = 'margelo.nitro.munimmaps'

const helperName = (element) => `__nitroVectorToArray_${element}`
const helper = (element) => `
/// munim-maps: see scripts/patch-nitro-vector-args.js (Xcode 26 cannot \`.map\` some std::vector arguments).
@inline(__always)
fileprivate func ${helperName(element)}(_ vector: ${NAMESPACE}.bridge.swift.std__vector_${element}_) -> [${element}] {
  let count = Int(vector.size())
  var result: [${element}] = []
  result.reserveCapacity(count)
  var index = 0
  while index < count {
    result.append(vector[index])
    index += 1
  }
  return result
}
`

const nestedHelper = (element) => `
@inline(__always)
fileprivate func ${helperName(element)}_nested(_ vector: ${NAMESPACE}.bridge.swift.std__vector_std__vector_${element}__) -> [[${element}]] {
  let count = Int(vector.size())
  var result: [[${element}]] = []
  result.reserveCapacity(count)
  var index = 0
  while index < count {
    result.append(${helperName(element)}(vector[index]))
    index += 1
  }
  return result
}
`

let patched = 0
const leftovers = []
for (const file of fs
  .readdirSync(swiftDir)
  .filter((name) => name.endsWith('.swift'))) {
  const filePath = path.join(swiftDir, file)
  const original = fs.readFileSync(filePath, 'utf8')
  const needed = new Set()
  const neededNested = new Set()
  // Each hybrid method: its signature, then its body up to the next member.
  let source = original.replace(
    /public final func (\w+)\(([^)]*)\)([^{]*)\{([\s\S]*?)(?=\n {2}@inline|\n {2}public|\n\})/g,
    (whole, name, params, rest, body) => {
      let newBody = body
      for (const match of params.matchAll(
        /(\w+): bridge\.std__vector_(\w+?)_(?=[,\s]|$)/g
      )) {
        const [, argument, element] = match
        const call = `${argument}.map({ __item in __item })`
        if (newBody.includes(call)) {
          newBody = newBody
            .split(call)
            .join(`${helperName(element)}(${argument})`)
          needed.add(element)
          patched++
        }
      }
      return `public final func ${name}(${params})${rest}{${newBody}`
    }
  )
  // Struct getters: `var name: [T] { return self.__name.map(...) }`, and
  // `[[T]]` (polygon holes) with the same conversion nested.
  source = source.replace(
    /(var \w+: \[(\[?)(\w+)\]?\] \{\n\s+return )self\.__(\w+)\.map\(\{ __item in __item(?:\.map\(\{ __item in __item \}\))? \}\)/g,
    (whole, head, nested, element, field) => {
      needed.add(element)
      if (nested) neededNested.add(element)
      patched++
      return `${head}${helperName(element)}${nested ? '_nested' : ''}(self.__${field})`
    }
  )
  for (const element of neededNested) {
    if (!source.includes(`func ${helperName(element)}_nested(`))
      source += nestedHelper(element)
  }
  for (const element of needed) {
    if (!source.includes(`func ${helperName(element)}(`))
      source += helper(element)
  }
  if (source !== original) fs.writeFileSync(filePath, source)

  for (const match of source.matchAll(
    /public final func \w+\(([^)]*)\)[^{]*\{([\s\S]*?)(?=\n {2}@inline|\n {2}public|\n\})/g
  )) {
    for (const param of match[1].matchAll(
      /(\w+): bridge\.std__vector_\w+?_/g
    )) {
      if (match[2].includes(`${param[1]}.map(`))
        leftovers.push(`${file}: ${param[1]}`)
    }
  }
}
for (const file of fs
  .readdirSync(swiftDir)
  .filter((name) => name.endsWith('.swift'))) {
  const text = fs.readFileSync(path.join(swiftDir, file), 'utf8')
  for (const match of text.matchAll(
    /var \w+: \[\[?\w+\]?\] \{\n\s+return self\.__(\w+)\.map\(/g
  )) {
    leftovers.push(`${file}: getter ${match[1]}`)
  }
}
if (leftovers.length > 0) {
  throw new Error(
    `patch-nitro-vector-args: vector arguments still use .map:\n${leftovers.join('\n')}`
  )
}
console.log(
  `patch-nitro-vector-args: rewrote ${patched} std::vector argument conversions`
)
