# TROUBLESHOOTING

## 1. Stage 9 would exit 70 on macOS: the system bash is 3.2

**Symptom.** Before the first full run, reading `lib/write_manifest.sh` showed a guard that exits 70 unless `BASH_VERSINFO` ≥ 4.3. `run_acceptance.sh` has the same guard.

**Evidence.** `bash --version` inside the `binf6610` env printed `GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`. So `bash run_pipeline.sh` and the `bash "${HERE}/lib/write_manifest.sh"` call in stage 9 were both resolving to `/bin/bash`. macOS ships bash 3.2 because later versions are GPLv3.

**Cause.** The env didn't provide its own bash, so `PATH` fell through to the system one.

**Fix.** Ran `conda install -c conda-forge bash` into the env, then `hash -r`. `bash --version` now reports `5.2.37`. The full run then reached stage 9 and wrote `manifest.json`.

`run_pipeline.sh` itself is kept bash-3.2-safe anyway: no `declare -A`, no `mapfile`, no `${x,,}`, and no `"${arr[@]}"` on a possibly-empty array under `set -u`. That way stage 0 still runs if someone launches it with `/bin/bash`.

## 2. `git push` failed: "Repository not found"

**Symptom.** `git push -u origin main` returned `remote: Repository not found`, both before and after pasting a token.

**Evidence.**
- Opening `https://github.com/aashisavla/binf6610-pipeline` in a browser gave a 404. So the problem wasn't authentication: the repository didn't exist.
- Separately, the first `git remote add origin https://github.com/<your-username>/…` had printed `zsh: no such file or directory: your-username`. zsh parses `<` as an input redirection, so that `remote add` never ran.

**Fix.** Created the repository through the GitHub API:
`curl -H "Authorization: token $TOKEN" https://api.github.com/user/repos -d '{"name":"binf6610-pipeline","private":false}'`
The response contained the repo's `html_url`, and the next `git push` succeeded.

## 3. GATK warnings: `libgkl_compression.dylib … incompatible architecture`

**Symptom.** Every GATK step logged `have 'x86_64', need 'arm64'` for the Intel GKL native library, followed by `IntelInflater is not supported, using Java.util.zip.Inflater`.

**Evidence it is harmless.**
- `MergeVcfs` reported `Tool returned: 0`.
- The stage-7 VCF has the columns `smoke_01 smoke_02 smoke_03` (2965 records, 2928 PASS).
- Scored against the wgsim truth files, the share of planted SNVs called non-reference was:

| sample | found | recall |
|---|---|---|
| smoke_01 | 850 / 850 | 100 % |
| smoke_02 | 828 / 829 | 99.9 % |
| smoke_03 (single-end, ~9×) | 798 / 866 | 92.1 % |

**Cause.** GKL ships only an x86_64 dylib, and this is an Apple Silicon Mac, so GATK falls back to Java's zlib. That's slower, not wrong. No fix needed on the laptop; Explorer is x86_64.

## Verification

The manifest's `git_sha` is `b6f1899…` with no `-dirty`: I committed before the run that went into `smoke-run/`. The acceptance suite passes all eight tests that don't need sequencing data.
