#!/usr/bin/env node
/**
 * The dotenv layer. One root .env is the single source of truth; every
 * per-application env file, ov.conf and the dsh profile patch are *rendered*
 * from it and overwritten on every run. Nothing downstream is hand-edited, so
 * a secret exists in exactly one place and a rebuilt host cannot drift.
 *
 *   render-env.mjs check        validate .env (required keys, placeholders)
 *   render-env.mjs apps         write every app's env file + ov.conf
 *   render-env.mjs dsh-patch    print the rendered cordis.patch.yml to stdout
 *   render-env.mjs all          check + apps
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync, chmodSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const ENV_PATH = process.env.STACK_ENV ?? join(ROOT, '.env')

// Keys with no safe default: the stack cannot work without them, so a missing
// one is a hard error rather than an empty string rendered into a config.
const REQUIRED = [
  'TRAEFIK_HOST', 'ACME_EMAIL',
  'JWT_SECRET', 'INITIAL_PASSWORD', 'API_KEY_SECRET', 'MACHINE_ID_SALT',
  'OPENVIKING_ROOT_API_KEY', 'NINEROUTER_API_KEY',
]

const DEFAULTS = {
  NODE22_VERSION: '22.21.1',
  DSH_VERSION: '0.2.2-rc.1',
  DSH_NODE_VERSION: '24.22.2',
  DSH_PORT: '3080',
  NINEROUTER_PROJECT: '9router-nxkt',
  NINEROUTER_PORT: '32768',
  TRAEFIK_PROJECT: 'traefik-twp8',
  HERMES_PROJECT: 'hermes-agent-qila',
  OPENVIKING_PORT: '1933',
  OPENVIKING_EMBED_MODEL: 'nomic-embed-text',
  OPENVIKING_EMBED_DIM: '768',
  OPENVIKING_EXTRACTION_MODEL: 'ds/deepseek-chat',
  HINDSIGHT_USER: 'hindsight',
  HINDSIGHT_PORT: '9077',
  HINDSIGHT_PROFILE: 'coding-agent',
  OPENVIKING_DIR: '/root/plugins/openviking-server',
}

export function parseEnv(text) {
  const out = {}
  for (const raw of text.split('\n')) {
    const line = raw.trim()
    if (!line || line.startsWith('#')) continue
    const eq = line.indexOf('=')
    if (eq < 1) continue
    const key = line.slice(0, eq).trim()
    let value = line.slice(eq + 1).trim()
    if (/^(["']).*\1$/s.test(value)) value = value.slice(1, -1)
    out[key] = value
  }
  return out
}

/** `${KEY}` substitution. An unknown or empty key is an error, not a blank. */
export function render(template, env, label = 'template') {
  const missing = new Set()
  const result = template.replace(/\$\{([A-Z0-9_]+)\}/g, (_, key) => {
    const value = env[key]
    if (value === undefined || value === '') { missing.add(key); return '' }
    return value
  })
  if (missing.size) {
    throw new Error(`${label}: no value for ${[...missing].join(', ')} — set it in .env`)
  }
  return result
}

function load() {
  if (!existsSync(ENV_PATH)) {
    console.error(`missing ${ENV_PATH} — copy .env.example and fill it in`)
    process.exit(1)
  }
  return { ...DEFAULTS, ...parseEnv(readFileSync(ENV_PATH, 'utf8')) }
}

function check(env) {
  const problems = []
  for (const key of REQUIRED) {
    if (!env[key]) problems.push(`${key} is empty`)
    else if (/^(xxx|changeme|tskey-auth-xxx)/i.test(env[key])) problems.push(`${key} still holds the example placeholder`)
  }
  if (env.TRAEFIK_HOST === 'example.com') problems.push('TRAEFIK_HOST is still example.com')
  if (problems.length) {
    console.error('.env is incomplete:')
    for (const p of problems) console.error(`  - ${p}`)
    process.exit(1)
  }
  console.log(`.env ok (${Object.keys(env).length} keys)`)
}

// target -> [template, destination, mode]
const TARGETS = (env) => [
  ['templates/9router.env.tmpl', `/docker/${env.NINEROUTER_PROJECT}/.env`, 0o600],
  ['templates/traefik.env.tmpl', `/docker/${env.TRAEFIK_PROJECT}/.env`, 0o600],
  ['templates/hermes.env.tmpl',  `/docker/${env.HERMES_PROJECT}/.env`, 0o600],
  ['templates/ov.conf.tmpl',     `${env.OPENVIKING_DIR}/ov.conf`, 0o600],
]

function writeApps(env) {
  for (const [tmpl, dest, mode] of TARGETS(env)) {
    const text = render(readFileSync(join(ROOT, tmpl), 'utf8'), env, tmpl)
    mkdirSync(dirname(dest), { recursive: true })
    writeFileSync(dest, text)
    chmodSync(dest, mode)   // these hold secrets: owner-only
    console.log(`rendered ${dest}`)
  }
}

// Importable: self-check.mjs reuses parseEnv/render, so the CLI must not run
// on import.
const invokedDirectly = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (!invokedDirectly) { /* imported as a module */ }
else main()

function main() {
const cmd = process.argv[2] ?? 'all'
const env = load()
if (cmd === 'check') check(env)
else if (cmd === 'apps') { check(env); writeApps(env) }
else if (cmd === 'dsh-patch') {
  process.stdout.write(render(readFileSync(join(ROOT, 'profiles/web/cordis.patch.yml.tmpl'), 'utf8'), env, 'cordis.patch.yml'))
} else if (cmd === 'all') { check(env); writeApps(env) }
else { console.error(`unknown target "${cmd}"`); process.exit(2) }
}
