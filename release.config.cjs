// Releases the munim-maps package (packages/munim-maps) from the repository
// root: `npm run release:local` (see scripts/release-local.mjs).
//
// munim-maps-vehicles (packages/munim-maps-vehicles) is versioned on its own
// and is not part of this release: its models only change with the vehicle
// catalogue, and its CDN URLs name its own version (VERSION in its
// index.js, which must match its package.json). Publish it by hand
// (`npm publish -w munim-maps-vehicles`) after changing it.
const rules = [
  { type: 'feat', release: 'minor', title: '✨ Features' },
  { type: 'fix', release: 'patch', title: '🐛 Bug Fixes' },
  { type: 'perf', release: 'patch', title: '💨 Performance Improvements' },
  { type: 'refactor', release: 'patch', title: '🔄 Code Refactors' },
  { type: 'docs', release: 'patch', title: '📚 Documentation' },
  { type: 'chore', release: 'patch', title: '🛠️ Other changes' },
]

const sortMap = Object.fromEntries(
  rules.map((rule, index) => [rule.title, index])
)

const pkgRoot = 'packages/munim-maps'

/**
 * @type {import('semantic-release').GlobalConfig}
 */
module.exports = {
  branches: ['main', { name: 'next', prerelease: 'next' }],
  tagFormat: 'v${version}',
  plugins: [
    [
      '@semantic-release/commit-analyzer',
      {
        preset: 'conventionalcommits',
        releaseRules: [
          { breaking: true, release: 'major' },
          { revert: true, release: 'patch' },
        ].concat(rules.map(({ type, release }) => ({ type, release }))),
      },
    ],
    [
      // CHANGELOG.md is Keep a Changelog: the [Unreleased] entries become the
      // release, or the commits' notes when there are none.
      './scripts/release-changelog.mjs',
      {
        changelogFile: 'CHANGELOG.md',
        commitNotes: {
          preset: 'conventionalcommits',
          presetConfig: {
            types: rules.map(({ type, title }) => ({
              type,
              section: title,
            })),
          },
          writerOpts: {
            commitGroupsSort: (a, z) => sortMap[a.title] - sortMap[z.title],
          },
        },
      },
    ],
    ['@semantic-release/npm', { pkgRoot }],
    [
      '@semantic-release/github',
      { releaseNameTemplate: 'munim-maps <%= nextRelease.version %>' },
    ],
    [
      '@semantic-release/git',
      {
        assets: [`${pkgRoot}/package.json`, 'package-lock.json', 'CHANGELOG.md'],
      },
    ],
  ],
}
