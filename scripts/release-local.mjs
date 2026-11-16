import { execFileSync, spawnSync } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const KEYCHAIN_ACCOUNT = 'sheehanmunim'
const KEYCHAIN_SERVICE = 'npm-token-munim-wifi' // shared npm token entry for all munim packages

function readCommand(command, args, description) {
  try {
    return execFileSync(command, args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
  } catch {
    console.error(`Unable to read ${description}.`)
    process.exit(1)
  }
}

function resolveNpmToken() {
  if (process.env.NPM_TOKEN) return process.env.NPM_TOKEN

  if (process.platform !== 'darwin') {
    console.error('Set NPM_TOKEN before running a local release on this platform.')
    process.exit(1)
  }

  return readCommand(
    'security',
    [
      'find-generic-password',
      '-a',
      KEYCHAIN_ACCOUNT,
      '-s',
      KEYCHAIN_SERVICE,
      '-w',
    ],
    `the npm token from macOS Keychain service ${KEYCHAIN_SERVICE}`
  )
}

function resolveGitHubToken() {
  if (process.env.GITHUB_TOKEN) return process.env.GITHUB_TOKEN
  if (process.env.GH_TOKEN) return process.env.GH_TOKEN

  return readCommand('gh', ['auth', 'token'], 'the GitHub CLI token')
}

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..'
)
const semanticRelease = path.join(
  repositoryRoot,
  'node_modules',
  'semantic-release',
  'bin',
  'semantic-release.js'
)
const npmConfigDirectory = mkdtempSync(
  path.join(tmpdir(), 'munim-maps-release-')
)
const npmUserConfig = path.join(npmConfigDirectory, '.npmrc')
writeFileSync(
  npmUserConfig,
  '//registry.npmjs.org/:_authToken=${NPM_TOKEN}\n',
  { mode: 0o600 }
)

let result
try {
  result = spawnSync(
    process.execPath,
    [semanticRelease, '--no-ci', ...process.argv.slice(2)],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        GITHUB_TOKEN: resolveGitHubToken(),
        NPM_CONFIG_USERCONFIG: npmUserConfig,
        NPM_TOKEN: resolveNpmToken(),
      },
      stdio: 'inherit',
    }
  )
} finally {
  rmSync(npmConfigDirectory, { force: true, recursive: true })
}

if (result.error) {
  console.error(result.error.message)
}

process.exit(result.status ?? 1)
