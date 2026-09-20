// Transpiles every CloudFront Function source in ../templates/src/ down to
// ../templates/dist/, the actual code Terraform deploys (see main.tf's
// aws_cloudfront_function.* resources, which read templates/dist/*.js via
// `file()`).
//
// Target es2019 specifically: it's the newest standard ECMAScript version
// that still contains everything cloudfront-js-2.0 natively supports (let/
// const, template literals, arrow functions, rest parameters, the `**`
// operator, async/await) while sitting *below* ES2020, where optional
// chaining (`?.`) and nullish coalescing (`??`) were introduced. Targeting
// es2019 makes esbuild downlevel those (and any other ES2020+ syntax) into
// es2019-compatible code, without also rewriting syntax cloudfront-js-2.0
// already handles natively (which a lower target, e.g. es5, would do
// unnecessarily and less predictably).
//
// See ../doc/cloudfront-js-runtime-compatibility.md for the full story on
// why this exists and what cloudfront-js-2.0 actually is.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, basename } from 'node:path';
import { transformSync } from 'esbuild';

const here = dirname(fileURLToPath(import.meta.url));
const srcDir = join(here, '..', 'templates', 'src');
const distDir = join(here, '..', 'templates', 'dist');

const sourceFiles = readdirSync(srcDir).filter((name) => name.endsWith('.js'));

if (sourceFiles.length === 0) {
  throw new Error(`No .js files found in ${srcDir}`);
}

for (const name of sourceFiles) {
  const srcPath = join(srcDir, name);
  const source = readFileSync(srcPath, 'utf8');

  // transformSync throws on esbuild errors, which is exactly what we want:
  // a syntax or transform failure here must fail the build, not silently
  // emit partial/garbage output.
  const result = transformSync(source, {
    target: ['es2019'],
    loader: 'js',
    sourcefile: name,
  });

  if (result.warnings.length > 0) {
    for (const warning of result.warnings) {
      console.warn(`[esbuild warning] ${name}: ${warning.text}`);
    }
  }

  const header =
    `// GENERATED FILE -- do not edit directly.\n` +
    `// Source: ../src/${name} -- regenerate via \`npm run build\` in edge-functions-build/.\n`;

  const outPath = join(distDir, basename(name));
  writeFileSync(outPath, header + result.code);
  console.log(`Built ${outPath} from ${srcPath}`);
}
