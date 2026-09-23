import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import fg from 'fast-glob';
import { dumpRegistry } from './fixture_variant_schema';

// Not a behavior test: a generator that runs under the integration jest config so module
// aliases and babel resolve. It globs every variant file, imports each one (which
// self-registers its variants via defineFixtureVariants), then writes a keys-only
// manifest of every query and its available variant keys. Run on demand:
//   yarn integration:variants
//
// It is excluded from the default jest:integration run (see
// testPathIgnorePatterns in jest.config.integration.js) so it only executes
// when explicitly invoked, not as a side effect of the full suite.
//
// The manifest is intentionally NOT committed: it is regenerated on demand and has
// no maintenance or drift cost. Devs and agents run the command, then read the file
// to discover which variants exist for which queries.

const SUITE_ROOT = join(__dirname, '..');
const OUT = join('tmp/tests/frontend/integration_variants.manifest.json');

async function importAllVariantFiles() {
  const files = fg.sync('**/fixture_variants/*.js', {
    cwd: SUITE_ROOT,
    absolute: true,
  });

  await Promise.all(files.map((file) => import(file)));

  return files.map((file) => relative(SUITE_ROOT, file));
}

describe('fixture variant manifest', () => {
  it('generates a keys-only manifest of every registered query and its variants', async () => {
    const importedFiles = await importAllVariantFiles();

    // No timestamp: the manifest is regenerated on demand, so there is no staleness
    // to track, and jest's faked clock would record a misleading "generated at" time.
    const manifest = {
      files: importedFiles.sort(),
      queries: dumpRegistry(),
    };

    mkdirSync(dirname(OUT), { recursive: true });
    writeFileSync(OUT, `${JSON.stringify(manifest, null, 2)}\n`);

    // eslint-disable-next-line no-console
    console.log(
      `Wrote ${Object.keys(manifest.queries).length} queries from ${importedFiles.length} files to ${OUT}`,
    );

    expect(Object.keys(manifest.queries).length).toBeGreaterThan(0);
  });
});
