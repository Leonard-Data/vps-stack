#!/usr/bin/env node
/**
 * The runnable check for the non-trivial logic in this repo: the dotenv
 * renderer. Rendering is where a mistake is expensive — a silently blank
 * `${KEY}` would write a config with an empty secret and the stack would fail
 * much later, somewhere else. So: substitution works, a missing key throws, and
 * every template only references keys .env.example actually defines.
 *
 * Run: node scripts/self-check.mjs
 */
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseEnv, render } from './render-env.mjs'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')

// 1. parseEnv: comments, blanks, quotes, and '=' inside a value.
const parsed = parseEnv([
  '# comment',
  '',
  'A=1',
  'B="two"',
  "C='three'",
  'D=key=with=equals',
].join('\n'))
assert.deepEqual(parsed, { A: '1', B: 'two', C: 'three', D: 'key=with=equals' })

// 2. render substitutes, and refuses to leave a hole.
assert.equal(render('x=${A}', { A: '1' }), 'x=1')
assert.throws(() => render('x=${MISSING}', {}), /no value for MISSING/)
assert.throws(() => render('x=${EMPTY}', { EMPTY: '' }), /no value for EMPTY/,
  'an empty value must fail like a missing one: an empty secret is not a secret')

// 3. Every ${KEY} in every template is defined in .env.example or has a
//    default in render-env.mjs. This is the check that catches a renamed key.
const example = parseEnv(readFileSync(join(ROOT, '.env.example'), 'utf8'))
const renderSrc = readFileSync(join(ROOT, 'scripts/render-env.mjs'), 'utf8')
const defaults = new Set([...renderSrc.matchAll(/^  ([A-Z0-9_]+):/gm)].map((m) => m[1]))

const templates = [
  ...readdirSync(join(ROOT, 'templates')).map((f) => join('templates', f)),
  'profiles/web/cordis.patch.yml.tmpl',
]
const unknown = []
for (const rel of templates) {
  const text = readFileSync(join(ROOT, rel), 'utf8')
  for (const [, key] of text.matchAll(/\$\{([A-Z0-9_]+)\}/g)) {
    if (!(key in example) && !defaults.has(key)) unknown.push(`${rel}: \${${key}}`)
  }
}
assert.deepEqual(unknown, [], `template keys with no source:\n  ${unknown.join('\n  ')}`)

// 4. The module list in install.sh and the files on disk must agree, so a
//    module cannot be added to one and forgotten in the other.
const installSh = readFileSync(join(ROOT, 'install.sh'), 'utf8')
const listed = [...installSh.matchAll(/^  (\d\d-[a-z-]+)/gm)].map((m) => m[1])
const onDisk = readdirSync(join(ROOT, 'modules')).filter((f) => f.endsWith('.sh')).map((f) => f.replace(/\.sh$/, '')).sort()
assert.deepEqual(listed.slice().sort(), onDisk, 'install.sh MODULES and modules/ disagree')
assert.deepEqual(listed, listed.slice().sort(), 'modules must be listed in execution order')

console.log(`self-check ok (${templates.length} templates, ${onDisk.length} modules)`)
