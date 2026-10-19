import { router } from '@kit.ArkUI';
import { TokenManager } from './HttpClient';

export function activateLogo(onHome: boolean = false): void {
  const auth = TokenManager.getInstance();
  if (!auth.isLoggedIn()) {
    if (router.getState().name !== 'LoginPage') router.replaceUrl({ url: 'pages/LoginPage' });
    return;
  }
  if (auth.mustChangePassword) {
    if (router.getState().name !== 'ChangePasswordPage') router.replaceUrl({ url: 'pages/ChangePasswordPage' });
    return;
  }
  if (onHome) {
    router.pushUrl({ url: 'pages/AboutPage' });
    return;
  }
  const homes = router.getStateByUrl('pages/HomePage');
  if (homes.length > 0) {
    router.back(homes[homes.length - 1].index);
  } else {
    router.replaceUrl({ url: 'pages/HomePage' }).then(() => { router.clear(); });
  }
}
