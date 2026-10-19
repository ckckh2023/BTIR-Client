const assert = require('node:assert/strict')
const { test } = require('node:test')
const { stripTypeScriptTypes } = require('node:module')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const root = path.resolve(__dirname, '../entry/src/main/ets')

function harness(native = {}) {
  let now = 0, sequence = 0
  const timers = new Map(), cache = new Map(), storage = new Map()
  class FakeDate extends Date { static now() { return now } }
  const sandbox = {
    Date: FakeDate, console, ArrayBuffer, Uint8Array,
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    setTimeout: (fn, delay) => { const id = ++sequence; timers.set(id, { at: now + delay, fn }); return id },
    clearTimeout: id => timers.delete(id),
  }
  function load(name, parent = root) {
    if (name.startsWith('@kit.')) return native[name] || {}
    const filename = path.resolve(parent, name.endsWith('.ets') ? name : name + '.ets')
    if (cache.has(filename)) return cache.get(filename)
    const source = fs.readFileSync(filename, 'utf8')
    const exports = {}; cache.set(filename, exports)
    const names = [...source.matchAll(/^export (?:class|function|const) (\w+)/gm)].map(match => match[1])
    let js = stripTypeScriptTypes(source, { mode: 'transform' })
    js = js.replace(/^import\s+\{([^}]+)\}\s+from\s+['"]([^'"]+)['"];?/gm,
      (_, values, dependency) => `const {${values.replace(/\bas\b/g, ':')}} = __load(${JSON.stringify(dependency)});`)
      .replace(/^export\s+(?=class|function|const)/gm, '')
    vm.runInNewContext(`(function(exports,__load){${js}\nObject.assign(exports,{${names.join(',')}})})`, sandbox,
      { filename })(exports, dependency => load(dependency, path.dirname(filename)))
    return exports
  }
  async function flush() { for (let i = 0; i < 12; i++) await Promise.resolve() }
  async function advance(ms) {
    const end = now + ms
    while (true) {
      const entries = [...timers.entries()].filter(([, timer]) => timer.at <= end).sort((a, b) => a[1].at - b[1].at)
      if (!entries.length) break
      const [id, timer] = entries[0]; now = timer.at; timers.delete(id); timer.fn(); await flush()
    }
    now = end; await flush()
  }
  return { load, timers, advance, flush, storage, setNow: value => { now = value } }
}
const task = (status, extra = {}) => ({ task_id: 'fixture', status, updated_at: '2026-10-19T00:00:00Z', ...extra })

test('progress matches web mapping and interpolation across phases and frame rates', t => {
  const reference = process.env.BTIR_WEB_FRONTEND || path.resolve(__dirname, '../../BTIR-BrainTumor-ImageRecognition/frontend')
  if (!fs.existsSync(path.join(reference, 'analysis-progress.js'))) return t.skip('Set BTIR_WEB_FRONTEND to compare the web implementation')
  const context = {}; vm.runInNewContext(fs.readFileSync(path.join(reference, 'analysis-progress.js'), 'utf8'), context)
  const { AnalysisProgress } = harness().load('./common/AnalysisProgress')
  for (const fps of [20, 30, 60]) {
    const mobile = new AnalysisProgress(), web = new context.BtirAnalysisProgress()
    let a = 0, b = 0
    for (let frame = 0; frame <= 170 * fps; frame++) {
      const now = frame * 1000 / fps, seconds = now / 1000
      const phase = seconds < 15 ? 'upload' : seconds < 25 ? 'queued' : seconds < 40 ? 'classification' : seconds < 150 ? 'segmentation' : seconds < 165 ? 'summary' : 'complete'
      const raw = seconds < 15 ? seconds / 15 * 36 : seconds < 40 ? 36 : seconds < 150 ? 44 + (seconds - 40) / 110 * 54 : seconds < 165 ? 99 : 100
      mobile.update(phase, raw, now); web.update(phase, raw, now)
      a = mobile.advance(a, now); b = web.advance(b, now)
      assert(Math.abs(a - b) < 1e-8)
      if (phase !== 'complete') assert(a < 100)
    }
    assert.equal(a, 100)
  }
})

test('queue and worker progress 100 cannot falsely complete analysis; reset supports retries', () => {
  const h = harness(), { AnalysisProgress } = h.load('./common/AnalysisProgress'), p = new AnalysisProgress()
  p.updateTask('queued', 36); assert.equal(p.target(600000), 10)
  assert.equal(p.phaseState(0, 'queued'), 'pending')
  p.updateTask('running', 36); assert.equal(p.phaseState(0, 'running'), 'active')
  p.updateTask('running', 44); assert.equal(p.mappedPercent, 20); assert.equal(p.phaseState(1, 'running'), 'active')
  p.updateTask('running', 71); p.updateTask('running', 44); assert.equal(p.raw, 71)
  p.updateTask('running', 100); assert(p.target(3600000) <= 99)
  assert.equal(p.phaseState(2, 'cancel_requested'), 'paused')
  p.reset(); p.updateTask('queued'); assert.equal(p.raw, 36)
})

test('monitor serializes requests and recovers from a transient failure, five repeated runs', async () => {
  for (let iteration = 0; iteration < 5; iteration++) {
    const h = harness(), { TaskMonitor } = h.load('./common/TaskMonitor')
    let calls = 0, resolve, current = null, errors = 0
    const monitor = new TaskMonitor(async () => {
      calls++; if (calls === 1) return new Promise(r => { resolve = r })
      if (calls === 2) throw new Error('temporary offline')
      return task('succeeded')
    }, response => { current = response.status }, failure => { assert(failure.retryInMs > 0); errors++ })
    monitor.start('fixture'); monitor.start('fixture'); assert.equal(calls, 1)
    resolve(task('running')); await h.flush(); await h.advance(500)
    assert.equal(errors, 1); assert.equal(current, 'running')
    await h.advance(1000); assert.equal(current, 'succeeded'); assert.equal(h.timers.size, 0)
    monitor.stop()
  }
})

test('monitor ignores old responses after leaving/restarting; terminal result stays terminal', async () => {
  const h = harness(), { TaskMonitor } = h.load('./common/TaskMonitor')
  const pending = [], displayed = []
  const monitor = new TaskMonitor(() => new Promise(r => pending.push(r)), response => displayed.push(response.status), () => assert.fail())
  monitor.start('old'); monitor.stop(); monitor.start('new')
  pending[1](task('failed')); await h.flush()
  pending[0](task('running')); await h.flush()
  assert.deepEqual(displayed, ['failed']); assert.equal(h.timers.size, 0)
})

test('authorization errors stop retries and 30-minute polling timeout is recoverable manually', async () => {
  for (const status of [401, 403, 404]) {
    const h = harness(), { TaskMonitor } = h.load('./common/TaskMonitor'), { ApiError } = h.load('./common/ApiError')
    let calls = 0
    const monitor = new TaskMonitor(async () => { calls++; throw new ApiError(status, 'fixture') }, () => assert.fail(), error => assert.equal(error.retryInMs, 0))
    monitor.start('fixture'); await h.flush(); await h.advance(100000)
    assert.equal(calls, 1); assert.equal(h.timers.size, 0)
  }
  const h = harness(), { TaskMonitor } = h.load('./common/TaskMonitor')
  let timeout = false, count = 0
  const monitor = new TaskMonitor(async () => { count++; return task('running') }, () => {}, failure => { timeout = failure.timedOut })
  monitor.start('fixture'); await h.flush(); h.setNow(1800000); await h.advance(500)
  assert(timeout); assert.equal(h.timers.size, 0)
  monitor.start('fixture'); await h.flush(); assert(count >= 2); monitor.stop()
})

test('structured conclusions, zero metrics and recommended-baseline-only responses are preserved', () => {
  const p = harness().load('./common/ResultPresentation')
  const negative = { level: 'high_probability_absent', label: '高概率不存在肿瘤相关区域', summary: '分类模型与分割模型均未提示异常区域' }
  assert.equal(p.consensusTone(negative), 'absent'); assert.equal(p.consensusLabel(negative), negative.label)
  assert.equal(p.consensusTone({ summary: '高概率不存在' }), 'review')
  assert.equal(p.evidenceLabel('segmentation'), '以分割结果为主要依据')
  assert.equal(p.formatMeasure(0), '0.0 mm³'); assert.equal(p.formatMeasure(NaN), '—')
  const metrics = p.imagingMetrics({ composites: { WT: { volume_mm3: 0 } }, morphology: { max_axial_area_mm2: 0 } })
  assert.equal(metrics.find(m => m.key === 'WT').value, '0.0 mm³')
  assert.equal(metrics.find(m => m.key === 'area').value, '0.0 mm²')
  const baseline = { task_id: 'base' }, result = { segmentation: {} }
  assert.equal(p.followUpHistory({ baseline, baseline_frontend_result: result, history: [] }).length, 1)
  assert.equal(p.followUpHistory({ baseline, baseline_frontend_result: result, history: [{ task: baseline, frontend_result: result }] }).length, 1)
  assert.equal(p.classificationLabel({ class: 'unknown' }), '分类结果待确认')
})

test('preview loader shows individual images, bounds concurrency, caches successes and retries missing images', async () => {
  const h = harness(), { PreviewLoader, previewManifest } = h.load('./common/PreviewLoader')
  const fixture = task('succeeded', { frontend_result: { result_files: { preview: 'overview', preview_series: { frames: [{ slice_index: 142, offset: 0, raw: 'raw', overlay: 'overlay' }, { slice_index: 143, offset: 1, raw: 'next' }] } } } })
  assert(previewManifest(fixture).some(item => item.label.includes('142')))
  const calls = [], pending = [], publishes = []
  let active = 0, maximum = 0, retry = false
  const loader = new PreviewLoader(async (_, path) => {
    calls.push(path); active++; maximum = Math.max(maximum, active)
    if (retry) { active--; return 'uri:' + path }
    return new Promise((resolve, reject) => pending.push({ path, resolve: value => { active--; resolve(value) }, reject: error => { active--; reject(error) } }))
  })
  const loading = loader.load(fixture, images => publishes.push(images))
  assert.equal(active, 3)
  pending[0].resolve('uri:overview'); await h.flush()
  assert.equal(publishes.at(-1).filter(image => image.uri).length, 1)
  pending[1].reject(new Error('one failed')); pending[2].resolve('uri:overlay'); await h.flush()
  pending[3].resolve('uri:next'); await loading
  assert.equal(maximum, 3)
  retry = true; await loader.load(fixture, images => publishes.push(images))
  assert.deepEqual(calls, ['overview', 'overlay', 'raw', 'next', 'overlay'])
})

test('superseded preview requests never publish stale images', async () => {
  const { PreviewLoader } = harness().load('./common/PreviewLoader')
  let resolve; const seen = []
  const loader = new PreviewLoader(() => new Promise(r => { resolve = r }))
  const loading = loader.load(task('succeeded', { frontend_result: { result_files: { preview: 'old' } } }), images => seen.push(images))
  loader.cancel(); resolve('old-uri'); await loading
  assert.equal(seen.length, 1); assert.equal(seen[0][0].uri, '')
})

test('report uses shared conclusion and metrics, escapes content and explains missing images', () => {
  const { buildReportHtml } = harness().load('./common/ReportPresentation')
  const html = buildReportHtml(task('partial', { name: '<script>fixture</script>', frontend_result: {
    model_consensus: { level: 'high_probability_absent', primary_evidence: 'segmentation' },
    segmentation: { composites: { WT: { volume_mm3: 0 } }, morphology: { max_axial_area_mm2: 12 } },
    result_files: { preview: 'missing' },
  } }), [])
  assert(html.includes('高概率不存在肿瘤相关区域')); assert(html.includes('以分割结果为主要依据'))
  assert(html.includes('0.0 mm³')); assert(html.includes('12.0 mm²'))
  assert(!html.includes('<script>fixture')); assert(html.includes('&lt;script&gt;fixture&lt;/script&gt;'))
  assert(html.includes('部分影像预览未能加载')); assert(html.includes('仅部分完成'))
})

test('server URLs normalize consistently and reject invalid or credential-bearing values', () => {
  const { normalizeServerUrl } = harness().load('./common/ServerUrl')
  assert.equal(normalizeServerUrl(' HTTPS://Example.COM/api/// '), 'https://example.com/api')
  assert.equal(normalizeServerUrl('http://[::1]:8000'), 'http://[::1]:8000')
  for (const url of ['example.com', 'file:///tmp/x', 'https://user:pass@host', 'https://host?x=1', 'http://host:99999', 'https://host/x y']) {
    assert.throws(() => normalizeServerUrl(url))
  }
})

test('file download closes the native request on success, HTTP failure and transport failure', async () => {
  for (const scenario of ['success', 'http', 'network']) {
    let destroyed = 0, options
    const http = { RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 'buffer' }, createHttp: () => ({
      request: async (_, config) => { options = config; if (scenario === 'network') throw new Error('offline'); return { responseCode: scenario === 'http' ? 404 : 200, result: new ArrayBuffer(1) } },
      destroy: () => destroyed++,
    }) }
    const h = harness({ '@kit.NetworkKit': { http }, '@kit.ArkTS': { buffer: { from: Buffer.from } } })
    const { HttpClient } = h.load('./common/HttpClient')
    const request = HttpClient.getInstance().downloadFile('/fixture')
    if (scenario === 'success') await request; else await assert.rejects(request)
    assert.equal(destroyed, 1); assert.equal(options.readTimeout, 30000); assert.equal(options.connectTimeout, 8000)
  }
})

test('ZIP and four-modality uploads report byte progress and keep multipart field names', async () => {
  for (const zip of [true, false]) {
    const percentages = []; let requestFields
    const http = { RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 'string' }, createHttp: () => {
      const handlers = {}
      return { on: (name, fn) => { handlers[name] = fn }, destroy() {}, request: async (_, options) => {
        requestFields = options.multiFormDataList.map(part => part.name)
        for (const size of [10, 30, 60]) handlers.dataSendProgress({ sendSize: size, totalSize: 100 })
        return { responseCode: 200, result: JSON.stringify({ task_id: 'fixture' }) }
      } }
    } }
    const fileIo = { OpenMode: { READ_ONLY: 0 }, open: async () => ({ fd: 1 }), close: async () => {},
      copyFile: async () => {}, stat: async () => ({ size: 100 }), unlink: async () => {},
      readSync: (_, target) => { const bytes = new Uint8Array(target); bytes.set([0x50, 0x4b, 5, 6], bytes.length - 22); return bytes.length },
    }
    const h = harness({ '@kit.NetworkKit': { http }, '@kit.CoreFileKit': { fileIo }, '@kit.BasicServicesKit': { deviceInfo: { productModel: 'phone' } } })
    const { TaskService } = h.load('./service/TaskService'), service = new TaskService()
    if (zip) await service.uploadArchive('fixture-uri', '/tmp', 'fixture.zip', { onProgress: value => percentages.push(value) })
    else await service.uploadNiftiFiles({ flair: 'a', t1ce: 'b', t1: 'c', t2: 'd' }, {}, '/tmp', undefined, undefined, undefined, undefined, undefined, value => percentages.push(value))
    assert.deepEqual(Array.from(requestFields), zip ? ['archive'] : ['flair', 't1ce', 't1', 't2'])
    assert.deepEqual(percentages, [10, 40, 100, 100])
  }
})

test('a new attempt or externally restarted task resets its previous completion state', () => {
  const { taskRunChanged } = harness().load('./common/TaskMonitor')
  const job = { id: 'same', attempt: 1 }
  assert(taskRunChanged(task('succeeded', { job }), task('running', { job })))
  assert(taskRunChanged(task('running', { job }), task('running', { job: { ...job, attempt: 2 } })))
  assert(!taskRunChanged(task('running', { job, progress: 44 }), task('running', { job, progress: 71 })))
  assert(!taskRunChanged(null, task('running')))
})


test('server selection survives a new config instance and failed persistence does not switch the active server', () => {
  const values = new Map()
  const store = { getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value), flushSync() {} }
  const { ApiConfig } = harness().load('./common/ApiConfig')
  const config = ApiConfig.getInstance(); config.initialize(store)
  assert.equal(config.setBaseUrl('HTTP://EXAMPLE.COM:8080/'), true)
  assert.equal(config.setBaseUrl('http://example.com:8080'), false)
  const restarted = harness().load('./common/ApiConfig').ApiConfig.getInstance()
  restarted.initialize(store); assert.equal(restarted.baseUrl, 'http://example.com:8080')
  restarted.initialize({ getSync: store.getSync, putSync() { throw new Error('disk unavailable') }, flushSync() {} })
  assert.throws(() => restarted.setBaseUrl('https://other.example'), /disk unavailable/)
  assert.equal(restarted.baseUrl, 'http://example.com:8080')
})

test('logo navigation returns to the existing home, opens About from home and respects auth gates', async () => {
  const calls = []
  let name = 'TaskDetailPage', homes = [{ index: 1 }]
  const router = {
    getState: () => ({ name }), getStateByUrl: () => homes,
    back: index => calls.push(['back', index]),
    pushUrl: options => calls.push(['push', options.url]),
    replaceUrl: async options => { calls.push(['replace', options.url]) },
    clear: () => calls.push(['clear']),
  }
  const h = harness({ '@kit.ArkUI': { router } })
  const { TokenManager } = h.load('./common/HttpClient')
  const { activateLogo } = h.load('./common/AppNavigation')
  const auth = TokenManager.getInstance()
  activateLogo(); assert.deepEqual(calls.pop(), ['replace', 'pages/LoginPage'])
  auth.setAuth('fixture', 'fixture', 'fixture', 'user', true)
  activateLogo(); assert.deepEqual(calls.pop(), ['replace', 'pages/ChangePasswordPage'])
  auth.setAuth('fixture', 'fixture', 'fixture', 'user', false)
  activateLogo(); assert.deepEqual(calls.pop(), ['back', 1])
  name = 'HomePage'; activateLogo(true); assert.deepEqual(calls.pop(), ['push', 'pages/AboutPage'])
  homes = []; name = 'AboutPage'; activateLogo(); await h.flush()
  assert.deepEqual(calls.splice(0), [['replace', 'pages/HomePage'], ['clear']])
})


test('sample catalogue matches web guide probabilities, volumes and public archive sizes', t => {
  const h = harness(), { SAMPLE_CASES, sampleSizeText } = h.load('./common/SampleCatalog')
  assert.equal(SAMPLE_CASES.length, 3)
  assert.equal(sampleSizeText(6716257), '6.7 MB')
  const reference = process.env.BTIR_WEB_FRONTEND || path.resolve(__dirname, '../../BTIR-BrainTumor-ImageRecognition/frontend')
  if (!fs.existsSync(path.join(reference, 'guide.html'))) return t.skip('Set BTIR_WEB_FRONTEND for the guide data contract')
  const html = fs.readFileSync(path.join(reference, 'guide.html'), 'utf8')
  const cards = html.split('<article class="guide-baseline-card">').slice(1)
  assert.equal(cards.length, SAMPLE_CASES.length)
  SAMPLE_CASES.forEach((sample, index) => {
    const card = cards[index].split('</article>')[0]
    assert(card.includes(sample.fileName)); assert(card.includes(sample.probability.toFixed(2) + '%'))
    for (const volume of [sample.wtCm3, sample.tcCm3, sample.etCm3]) assert(card.includes(volume.toFixed(1) + ' cm³'))
    const archive = path.join(reference, '../assets/samples', sample.fileName)
    if (fs.existsSync(archive)) assert.equal(fs.statSync(archive).size, sample.sizeBytes)
  })
})

test('imaging feature ratios preserve zeros, avoid zero denominators and bound noisy backend ratios', () => {
  const { imagingMetrics } = harness().load('./common/ResultPresentation')
  const metrics = imagingMetrics({ regions: { '2': { volume_mm3: 25 } },
    composites: { WT: { volume_mm3: 100 }, TC: { volume_mm3: 10 }, ET: { volume_mm3: 0 } },
    morphology: { connected_components: 2, largest_component_ratio: 1.1 } })
  assert.equal(metrics.find(item => item.key === 'edema').value, '25.0%')
  assert.equal(metrics.find(item => item.key === 'enhancement').value, '0.0%')
  assert.equal(metrics.find(item => item.key === 'distribution').meter, 100)
  const empty = imagingMetrics({ regions: { '2': { volume_mm3: 0 } },
    composites: { WT: { volume_mm3: 0 }, TC: { volume_mm3: 0 }, ET: { volume_mm3: 0 } } })
  assert(!empty.some(item => item.key === 'edema' || item.key === 'enhancement'))
  assert(empty.some(item => item.key === 'WT' && item.value === '0.0 mm³'))
})

test('probability curve retains real slice numbers, orders them and rejects invalid probabilities', () => {
  const p = harness().load('./common/ProbabilityPresentation')
  const source = [{ slice_index: 143, yes_probability: 1 }, { slice_index: 142, yes_probability: 0 },
    { slice_index: 144, yes_probability: 2 }, { slice_index: -1, yes_probability: .5 }]
  const series = p.probabilitySeries({ slice_probability_series: source })
  assert.deepEqual(Array.from(series, item => item.slice_index), [142, 143])
  assert.equal(source[0].slice_index, 143)
  assert.equal(p.probabilitySeries({ slice_probability_series: {} }).length, 0)
  assert.equal(p.probabilityThreshold({ threshold: 0 }), 0)
  assert.equal(p.probabilityThreshold({ threshold: NaN }), .548381)
})
