export interface SampleCase {
  title: string;
  fileName: string;
  sizeBytes: number;
  probability: number;
  wtCm3: number;
  tcCm3: number;
  etCm3: number;
}

// 与主项目 guide.html 的公开样例、核对值及 assets/samples 文件一致。
export const SAMPLE_CASES: SampleCase[] = [
  { title: '病例 1', fileName: 'BraTS19_2013_2_1.zip', sizeBytes: 6716257, probability: 61.27, wtCm3: 75.1, tcCm3: 41.3, etCm3: 2.8 },
  { title: '病例 2', fileName: 'BraTS19_2013_4_1.zip', sizeBytes: 7163058, probability: 71.65, wtCm3: 164.8, tcCm3: 65.5, etCm3: 38.0 },
  { title: '病例 3', fileName: 'BraTS19_2013_7_1.zip', sizeBytes: 7907474, probability: 73.74, wtCm3: 134.1, tcCm3: 44.3, etCm3: 28.7 }
];

export function sampleSizeText(bytes: number): string { return `${(bytes / 1000000).toFixed(1)} MB`; }
