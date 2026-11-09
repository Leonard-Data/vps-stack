#!/usr/bin/env node
/**
 * Print the CHANGELOG section for one version, for use as GitHub Release notes.
 *
 * Run: node scripts/release-notes.mjs v1.2.3
 */
import { readFileSync } from 'node:fs'

const tag = process.argv[2] ?? ''
const version = tag.replace(/^v/, '')
if (!/^\d+\.\d+\.\d+$/.test(version)) {
  console.error(`Usage: release-notes.mjs vX.Y.Z (got "${tag}")`)
  process.exit(1)
}

const changelog = readFileSync(new URL('../CHANGELOG.md', import.meta.url), 'utf8')
const lines = changelog.split('\n')
const escaped = version.replace(/\./g, '\\.')
const start = lines.findIndex((line) => new RegExp(`^##\\s+\\[?v?${escaped}\\]?`).test(line))
if (start === -1) {
  console.error(`CHANGELOG.md has no section for ${version}.`)
  process.exit(1)
}
let end = lines.length
for (let i = start + 1; i < lines.length; i += 1) {
  if (/^##\s/.test(lines[i])) { end = i; break }
}
process.stdout.write(lines.slice(start + 1, end).join('\n').trim() + '\n')
