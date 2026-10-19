// Synthetic download benchmark. See docs/MOBILE-PARITY.md for baseline extraction.
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const { stripTypeScriptTypes } = require('node:module')
const { performance } = require('node:perf_hooks')

const baseline = fs.readFileSync(process.env.BTIR_PREVIEW_BASELINE || '/tmp/btir-detail-baseline.ets', 'utf8')
const body = baseline.split('async loadPreviewImages(task: TaskStatusResponse): Promise<void> {')[1]
  .split('\n  arrayBufferToBase64(')[0].replace(/\n  }\s*$/, '')
const beforeLoad = vm.runInNewContext(stripTypeScriptTypes('(async function(task: Object){' + body + '})', { mode: 'transform' }))
const source = stripTypeScriptTypes(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/common/PreviewLoader.ets'), 'utf8'), { mode: 'transform' })
  .replace(/^import[^;]+;/gm, '').replace(/^export /gm, '')
const { PreviewLoader } = vm.runInNewContext('(function(){' + source + ';return {PreviewLoader}})()')
const fixture = {
  task_id: 'fixture', updated_at: 'fixed', frontend_result: { result_files: {
    preview: 'overview', preview_series: { frames: [0, 1, 2].map(index => ({
      slice_index: 140 + index, raw: 'raw' + index, overlay: 'overlay' + index,
    })) },
  } },
}
const download = () => new Promise(resolve => setTimeout(() => resolve(new ArrayBuffer(1)), 60))
function stats(values) {
  const sorted = values.slice().sort((a, b) => a - b)
  return {
    median_ms: +sorted[Math.floor(sorted.length / 2)].toFixed(1),
    min_ms: +sorted[0].toFixed(1), max_ms: +sorted.at(-1).toFixed(1),
  }
}

async function main() {
  const before = [], after = [], complete = []
  for (let run = 0; run < 5; run++) {
    const state = { taskService: { downloadFile: download }, arrayBufferToBase64: () => 'fixture', previewImageUris: {} }
    const start = performance.now()
    await beforeLoad.call(state, fixture)
    before.push(performance.now() - start)
    if (Object.keys(state.previewImageUris).length !== 7) throw Error('Baseline work mismatch')

    const loader = new PreviewLoader(async () => { await download(); return 'data:image/png;base64,fixture' })
    const nextStart = performance.now()
    let first = null, final = []
    await loader.load(fixture, items => {
      final = items
      if (first === null && items.some(item => item.uri)) first = performance.now() - nextStart
    })
    after.push(first)
    complete.push(performance.now() - nextStart)
    if (final.filter(item => item.uri).length !== 7) throw Error('Updated work mismatch')
  }
  console.log(JSON.stringify({
    workload: '7 synthetic images, each download delayed 60 ms, fresh loader per run', samples: 5,
    before_first_image: stats(before), after_first_image: stats(after), after_all_images: stats(complete),
  }, null, 2))
}
main().catch(error => { console.error(error); process.exitCode = 1 })
