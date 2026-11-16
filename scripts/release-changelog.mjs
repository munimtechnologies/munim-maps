// semantic-release plugin for this repo's CHANGELOG.md, which follows Keep a
// Changelog: entries are written by hand under "## [Unreleased]" and each
// release turns them into "## [x.y.z] - YYYY-MM-DD".
//
// generateNotes: the "## [Unreleased]" entries when there are any; otherwise
//   notes generated from the conventional commits since the last release.
//   Either way they are the GitHub release's notes.
// prepare: writes those notes under a new "## [x.y.z] - YYYY-MM-DD" heading
//   below an empty "## [Unreleased]", and moves the compare links at the end
//   of the file (if it has them) along.
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'

const UNRELEASED_HEADING = /^## \[Unreleased\][^\n]*\n/m
// The next release heading, or the link definitions at the end of the file.
const SECTION_END = /^## \[|^\[[^\]\n]+\]: /m

function changelogPath(pluginConfig, cwd) {
  return path.resolve(cwd, pluginConfig.changelogFile ?? 'CHANGELOG.md')
}

function splitUnreleased(text, file) {
  const heading = text.match(UNRELEASED_HEADING)
  if (!heading) {
    throw new Error(`${file} has no "## [Unreleased]" heading`)
  }
  const start = heading.index + heading[0].length
  const next = text.slice(start).search(SECTION_END)
  const end = next === -1 ? text.length : start + next
  return {
    before: text.slice(0, start),
    entries: text.slice(start, end).trim(),
    after: text.slice(end),
  }
}

function localDate() {
  // YYYY-MM-DD in the releasing machine's time zone, like the dates above.
  return new Date().toLocaleDateString('en-CA')
}

async function commitNotes(pluginConfig, context) {
  const { generateNotes } = await import(
    '@semantic-release/release-notes-generator'
  )
  const notes = await generateNotes(pluginConfig.commitNotes ?? {}, context)
  // Drop the generator's "## [x.y.z](compare) (date)" heading; prepare
  // writes the heading this file uses.
  return notes.replace(/^#{1,3} .*\n+/, '').trim()
}

export async function verifyConditions(pluginConfig, { cwd }) {
  const file = changelogPath(pluginConfig, cwd)
  splitUnreleased(await readFile(file, 'utf8'), file)
}

export async function generateNotes(pluginConfig, context) {
  const file = changelogPath(pluginConfig, context.cwd)
  const { entries } = splitUnreleased(await readFile(file, 'utf8'), file)
  if (entries) {
    context.logger.log('Release notes: the [Unreleased] entries of %s', file)
    return entries
  }
  context.logger.log(
    'Release notes: %s has no [Unreleased] entries, using the commits',
    file
  )
  return commitNotes(pluginConfig, context)
}

export async function prepare(pluginConfig, context) {
  const { cwd, lastRelease, nextRelease, logger } = context
  const file = changelogPath(pluginConfig, cwd)
  const { before, after } = splitUnreleased(await readFile(file, 'utf8'), file)
  const notes = (nextRelease.notes ?? '').trim()
  const date = pluginConfig.date ?? localDate()

  let text = `${before}\n## [${nextRelease.version}] - ${date}\n\n${notes}\n\n${after}`
  text = text.replace(
    /^\[Unreleased\]: (\S*\/compare\/)(\S+)\.\.\.HEAD$/m,
    (_, base, previous) =>
      `[Unreleased]: ${base}${nextRelease.gitTag}...HEAD\n` +
      `[${nextRelease.version}]: ${base}${lastRelease?.gitTag || previous}...${nextRelease.gitTag}`
  )

  await writeFile(file, text)
  logger.log('Wrote %s %s to %s', nextRelease.version, date, file)
}
