const fs = require('node:fs');
const path = require('node:path');
const { homedir } = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { parseArgs } = require('node:util');
const json5 = require('json5');
const root = path.resolve(__dirname, '..');
const lock = require('./template-lock.json');
const pkg = require('../package.json');
const project = path.join(root, 'release/harmony-project');
const bundleName = 'cn.btir.client.pc';
const { values: options, positionals } = parseArgs({ allowPositionals: true, options: {
  debug: { type: 'boolean' }, unsigned: { type: 'boolean' },
  input: { type: 'string' }, output: { type: 'string' }, template: { type: 'string' },
} });
const kind = options.debug ? 'debug' : 'release';
const output = path.join(root, `release/BTIR-PC-${kind}`);
const unsigned = path.resolve(options.input || `${output}-unsigned.hap`);
const signed = path.resolve(options.output || `${output}-signed.hap`);
const tool = process.env.BTIR_HAP_SIGN_TOOL || path.join(homedir(), '.local/share/harmonyos/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar');

function run(executable, args, cwd = root, capture = false, env = {}) {
  const result = spawnSync(executable, args, { cwd, stdio: capture ? 'pipe' : 'inherit', env: { ...process.env, ...env }, timeout: 600000, maxBuffer: 512 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`${executable} 执行失败：${result.error?.message || result.status}`);
  return result.stdout;
}
function read(file) { return json5.parse(fs.readFileSync(file, 'utf8')); }
function write(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
}
function edit(relative, fn) { const file = path.join(project, relative); const data = read(file); fn(data); write(file, data); }
function syncApp() {
  const app = path.join(project, 'web_engine/src/main/resources/resfile/resources/app');
  fs.rmSync(app, { recursive: true, force: true });
  fs.mkdirSync(app, { recursive: true });
  for (const folder of ['electron', 'renderer']) fs.cpSync(path.join(root, folder), path.join(app, folder), { recursive: true });
  fs.copyFileSync(path.join(root, 'LICENSE'), path.join(app, 'LICENSE'));
  write(path.join(app, 'package.json'), { name: pkg.name, version: pkg.version, description: pkg.description, main: pkg.main, license: pkg.license });
  const [major, minor, patch] = pkg.version.split('.').map(Number);
  if (![major, minor, patch].every(Number.isInteger)) throw new Error('应用版本必须是 major.minor.patch');
  edit('AppScope/app.json5', data => { data.app.versionName = pkg.version; data.app.versionCode = major * 1000000 + minor * 1000 + patch; });
}
function verifyTemplate(template) {
  if (run('git', ['rev-parse', 'HEAD'], template, true).toString().trim() !== lock.commit) throw new Error('模板提交与 template-lock.json 不一致');
  for (const [name, sha] of Object.entries(lock.libraries)) {
    const bytes = fs.readFileSync(path.join(template, 'electron/libs', lock.architecture, name));
    if (bytes.subarray(0, 4).toString('hex') !== '7f454c46' || bytes.readUInt16LE(18) !== 183) throw new Error(`${name} 不是 ARM64 ELF，请检查 Git LFS`);
    if (crypto.createHash('sha256').update(bytes).digest('hex') !== sha) throw new Error(`${name} SHA-256 不匹配`);
  }
}
function prepare() {
  const template = path.resolve(options.template || process.env.BTIR_HARMONY_TEMPLATE || path.join(root, 'release/harmony-template'));
  if (fs.existsSync(project)) throw new Error('工程已存在。为保护签名配置，不覆盖；重新生成前请先移走 release/harmony-project。');
  if (!fs.existsSync(template)) {
    fs.mkdirSync(path.dirname(template), { recursive: true });
    run('git', ['clone', '--no-checkout', lock.repository, template], root, false, { GIT_LFS_SKIP_SMUDGE: '1' });
    run('git', ['checkout', '--detach', lock.commit], template, false, { GIT_LFS_SKIP_SMUDGE: '1' });
    run('git', ['lfs', 'pull', '--include=electron/libs/arm64-v8a/*.so'], template);
  }
  verifyTemplate(template);
  fs.mkdirSync(project, { recursive: true });
  for (const name of ['AppScope', 'electron', 'web_engine', 'hvigor', 'hvigorfile.ts', 'build-profile.json5', 'oh-package.json5']) {
    fs.cpSync(path.join(template, name), path.join(project, name), { recursive: true, filter: source => !source.split(path.sep).some(part => ['oh_modules', '.hvigor', '.signing', 'build', 'ohosTest'].includes(part)) });
  }
  fs.writeFileSync(path.join(project, '.npmrc'), '@ohos:registry=https://repo.harmonyos.com/npm/\n');
  edit('AppScope/app.json5', data => { Object.assign(data.app, { bundleName, vendor: 'BTIR' }); delete data.app.multiAppMode; });
  edit('build-profile.json5', data => {
    delete data.app.signingConfigs;
    for (const product of data.app.products) {
      delete product.signingConfig;
      delete product.compatibleSdkVersionStage;
      product.compatibleSdkVersion = '5.1.0(18)';
      product.targetSdkVersion = '26.0.0';
    }
  });
  edit('hvigor/hvigor-config.json5', data => { data.dependencies = { '@ohos/hvigor-ohos-plugin': '6.26.8' }; });
  edit('oh-package.json5', data => { Object.assign(data, { name: 'btir-harmony-pc', version: pkg.version, license: 'MIT', description: pkg.description, devDependencies: {} }); });
  edit('electron/build-profile.json5', data => { data.targets = data.targets.filter(target => target.name !== 'ohosTest'); });
  edit('electron/src/main/module.json5', data => {
    data.module.deviceTypes = ['2in1'];
    data.module.abilities.find(ability => ability.name === 'EntryAbility').metadata = [
      { name: 'ohos.ability.window.width', value: '1366' }, { name: 'ohos.ability.window.height', value: '860' },
      { name: 'ohos.ability.window.left', value: 'center' }, { name: 'ohos.ability.window.top', value: 'center' },
    ];
  });
  edit('web_engine/src/main/module.json5', data => {
    data.module.deviceTypes = ['2in1'];
    const needed = new Set(['ohos.permission.INTERNET', 'ohos.permission.GET_NETWORK_INFO', 'ohos.permission.RUNNING_LOCK', 'ohos.permission.PRINT', 'ohos.permission.PREPARE_APP_TERMINATE', 'ohos.permission.FILE_ACCESS_PERSIST', 'ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY']);
    data.module.requestPermissions = data.module.requestPermissions.filter(permission => needed.has(permission.name));
  });
  const adapter = path.join(project, 'web_engine/src/main/ets/adapter/AppWindowAdapter.ets');
  const code = fs.readFileSync(adapter, 'utf8');
  if (!code.includes('processMode: contextConstant.ProcessMode.ATTACH_TO_STATUS_BAR_ITEM')) throw new Error('模板窗口结构发生变化');
  fs.writeFileSync(adapter, code.replace(/^.*processMode: contextConstant.ProcessMode.ATTACH_TO_STATUS_BAR_ITEM,\r?\n/m, '').replace(/^.*startupVisibility: param.show \?.*\r?\n/m, ''));
  for (const base of ['AppScope/resources', 'electron/src/main/resources']) {
    const visit = dir => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const file = path.join(dir, entry.name);
        if (entry.isDirectory()) visit(file);
        else if (entry.name === 'string.json') {
          const data = read(file);
          for (const value of data.string || []) if (['app_name', 'EntryAbility_label'].includes(value.name)) value.value = 'BTIR 智瞳医脑';
          write(file, data);
        }
      }
    };
    visit(path.join(project, base));
  }
  for (const name of ['app_icon.png', 'startIcon.png', 'product_logo_32.png']) fs.copyFileSync(path.join(root, 'build/icon.png'), path.join(project, 'AppScope/resources/base/media', name));
  syncApp();
  write(path.join(project, 'btir-build-info.json'), { bundleName, architecture: lock.architecture, templateCommit: lock.commit, runtimeTested: false });
}
function build() {
  if (!fs.existsSync(project)) prepare();
  if (read(path.join(project, 'btir-build-info.json')).templateCommit !== lock.commit) throw new Error('生成工程与模板版本不匹配');
  syncApp();
  run('ohpm', ['install'], project);
  const args = options.debug
    ? ['assembleHap', '-p', 'module=electron@default']
    : ['assembleApp', '--mode', 'project'];
  run('hvigorw', [...args, '-p', 'product=default', '-p', `buildMode=${kind}`, '--no-daemon', '--error'], project);
  fs.copyFileSync(path.join(project, 'electron/build/default/outputs/default/electron-default-unsigned.hap'), unsigned);
  if (!options.debug) {
    const directory = path.join(project, 'build/outputs/default');
    const app = fs.readdirSync(directory).find(name => name.endsWith('-unsigned.app'));
    if (!app) throw new Error('未找到 Release APP');
    fs.copyFileSync(path.join(directory, app), `${output}-unsigned.app`);
  }
}
function zip(hap, name) { return run('unzip', ['-p', hap, name], root, true); }
function checkPackage(hap, isSigned = false) {
  run('unzip', ['-tqq', hap], root, true);
  const data = JSON.parse(zip(hap, 'module.json'));
  if (data.app.bundleName !== bundleName || JSON.stringify(data.module.deviceTypes) !== '["2in1"]') throw new Error('HAP 包名或设备类型错误');
  if (kind === 'release' && (data.app.debug !== false || data.app.buildMode !== 'release')) throw new Error('需要 Release 构建');
  if (data.app.versionName !== pkg.version) throw new Error('HAP 版本已过期');
  const names = run('unzip', ['-Z1', hap], root, true).toString().trim().split(/\r?\n/);
  if (!names.includes('ets/modules.abc') || names.some(name => name.split('/').some(part => ['.git', '.signing', 'node_modules'].includes(part)))) throw new Error('HAP 字节码缺失或包含开发目录');
  const prefix = 'resources/resfile/resources/app/';
  if (JSON.parse(zip(hap, prefix + 'package.json')).main !== 'electron/main.js') throw new Error('HAP 入口错误');
  const visit = directory => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const source = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(source);
      else if (entry.isFile() && !zip(hap, prefix + path.relative(root, source).split(path.sep).join('/')).equals(fs.readFileSync(source))) throw new Error(`HAP 内容缺失或过期：${path.relative(root, source)}`);
    }
  };
  for (const folder of ['electron', 'renderer']) visit(path.join(root, folder));
  for (const [name, sha] of Object.entries(lock.libraries)) {
    const bytes = zip(hap, `libs/${lock.architecture}/${name}`);
    if (bytes.subarray(0, 4).toString('hex') !== '7f454c46' || bytes.readUInt16LE(18) !== 183) throw new Error(`${name} 不是 ARM64 ELF`);
    if (!isSigned && crypto.createHash('sha256').update(bytes).digest('hex') !== sha) throw new Error(`${name} 运行库校验失败`);
  }
  console.log(`包内容校验通过：${hap}`);
  return data;
}
function official(args, interactive = false) {
  if (!fs.existsSync(tool)) throw new Error('请设置 BTIR_HAP_SIGN_TOOL 指向 SDK 的 hap-sign-tool.jar');
  return run('java', ['-jar', tool, ...args], root, !interactive);
}
function validateProfile(file, data, certificate, udidFile) {
  // CMS integrity is checked locally; device trust still requires PC installation.
  const profile = JSON.parse(run('openssl', ['cms', '-verify', '-inform', 'DER', '-in', file, '-noverify'], root, true));
  const info = profile['bundle-info'] || {};
  if (info['bundle-name'] !== bundleName || profile.type !== kind) throw new Error(`需要 ${bundleName} 的 ${kind} Profile`);
  const now = Date.now() / 1000;
  if (!(profile.validity?.['not-before'] <= now && now <= profile.validity?.['not-after'])) throw new Error('Profile 尚未生效或已过期');
  if (options.debug && !profile['debug-info']?.['device-ids']?.length) throw new Error('调试 Profile 未授权设备');
  if (udidFile) {
    const udid = fs.readFileSync(udidFile, 'utf8').trim();
    if (!udid || !profile['debug-info']?.['device-ids']?.includes(udid)) throw new Error('目标电脑 UDID 未获授权');
  }
  const permissions = read(path.join(path.dirname(tool), 'PermissionDefinitions.json')).definePermissions;
  const levels = { normal: 0, system_basic: 1, system_core: 2 };
  if (!(info.apl in levels)) throw new Error('Profile 权限级别无效');
  for (const request of data.module.requestPermissions || []) {
    const definition = permissions.find(permission => permission.name === request.name);
    if (!definition || !(definition.availableLevel in levels)) throw new Error(`SDK 中找不到权限定义：${request.name}`);
    if (levels[definition.availableLevel] > levels[info.apl] && !profile.acls?.['allowed-acls']?.includes(request.name)) throw new Error(`Profile 缺少 ACL：${request.name}`);
  }
  if (certificate) {
    const embedded = new crypto.X509Certificate(info[kind === 'release' ? 'distribution-certificate' : 'development-certificate']);
    const chain = fs.readFileSync(certificate, 'utf8').match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g) || [];
    if (!chain.some(pem => new crypto.X509Certificate(pem).raw.equals(embedded.raw))) throw new Error('证书与 Profile 不匹配');
    if (Date.parse(embedded.validFrom) > Date.now() || Date.parse(embedded.validTo) < Date.now()) throw new Error('应用证书尚未生效或已过期');
  }
}
function materials() {
  const file = path.join(root, '.signing', options.debug ? 'signing.local.json' : 'signing.release.local.json');
  const config = read(file);
  for (const name of ['keystore', 'certificate', 'profile', ...(options.debug ? ['udid_file'] : [])]) {
    if (!config[name]) throw new Error(`签名配置缺少 ${name}`);
    config[name] = path.resolve(path.dirname(file), config[name].replace(/^~(?=[/\\]|$)/, homedir()));
    if (!fs.existsSync(config[name])) throw new Error(`签名材料缺失：${name}`);
  }
  if (!config.alias) throw new Error('签名配置缺少 alias');
  return config;
}
function verify(hap, data, udidFile) {
  const directory = fs.mkdtempSync(path.join(root, 'release/.harmony-verify-'));
  try {
    const profile = path.join(directory, 'profile.p7b');
    official(['verify-app', '-inFile', hap, '-outCertChain', path.join(directory, 'chain.cer'), '-outProfile', profile]);
    validateProfile(profile, data, null, udidFile);
    console.log('官方验签通过；安装和运行仍需鸿蒙电脑实测。');
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
}
function sign(data, config) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error('请在本地交互终端签名，按提示输入密码');
  if (fs.existsSync(signed)) throw new Error('签名包已存在，请用 --output 指定新文件');
  fs.mkdirSync(path.dirname(signed), { recursive: true });
  const directory = fs.mkdtempSync(path.join(path.dirname(signed), '.harmony-sign-'));
  try {
    const temporary = path.join(directory, 'signed.hap');
    official(['verify-profile', '-inFile', config.profile, '-outFile', path.join(directory, 'profile.json')]);
    official(['sign-app', '-mode', 'localSign', '-keyAlias', config.alias, '-keystoreFile', config.keystore,
      '-appCertFile', config.certificate, '-profileFile', config.profile, '-profileSigned', '1',
      '-inFile', unsigned, '-outFile', temporary, '-signAlg', 'SHA256withECDSA',
      '-compatibleVersion', String(Number(data.app.minAPIVersion) % 1000000), '-signCode', '1', '-pwdInputMode', '1'], true);
    verify(temporary, checkPackage(temporary, true), options.debug ? config.udid_file : null);
    fs.linkSync(temporary, signed);
    console.log(`已生成：${signed}`);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
}
try {
  const action = positionals[0] || 'build';
  if (positionals.length > 1 || !['build', 'sign', 'check', 'verify'].includes(action)) throw new Error('用法：npm run dist:harmony -- [build|sign|check|verify] [--debug] [--unsigned]');
  if (action === 'build') build();
  const file = action === 'verify' ? path.resolve(options.input || signed) : unsigned;
  const data = checkPackage(file, action === 'verify');
  if (action === 'verify') verify(file, data);
  else if (!options.unsigned) {
    const config = materials();
    validateProfile(config.profile, data, config.certificate, options.debug ? config.udid_file : null);
    if (action !== 'check') sign(data, config);
    else console.log('签名材料检查通过。');
  }
} catch (error) { console.error(error.message); process.exitCode = 1; }
