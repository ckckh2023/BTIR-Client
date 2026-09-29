#!/usr/bin/env node
import { hvigor } from '@ohos/hvigor';
import { ohosPlugin } from '@ohos/hvigor-ohos-plugin';

hvigor.init({
  plugins: [ohosPlugin],
});

hvigor.run();
