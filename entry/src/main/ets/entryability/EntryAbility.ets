import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { ApiConfig } from '../common/ApiConfig';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      ApiConfig.getInstance().initialize(preferences.getPreferencesSync(this.context, { name: 'btir-settings' }));
    } catch (error) { console.error('Unable to load server settings'); }
    console.info('EntryAbility onCreate');
  }

  onDestroy(): void {
    console.info('EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('EntryAbility onWindowStageCreate');
    windowStage.getMainWindow((err, mainWindow) => {
      if (err.code) {
        console.error('Failed to get main window. code:' + JSON.stringify(err));
        return;
      }
      const updateInsets = (): void => {
        const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const uiContext = mainWindow.getUIContext();
        AppStorage.setOrCreate<number>('system_top_inset', uiContext.px2vp(area.topRect.height));
        AppStorage.setOrCreate<number>('system_bottom_inset', uiContext.px2vp(area.bottomRect.height));
      };
      mainWindow.setUIContent('pages/LoginPage', (err) => {
        if (err.code) {
          console.error('Failed to load content. code:' + JSON.stringify(err));
          return;
        }
        updateInsets();
        mainWindow.on('avoidAreaChange', updateInsets);
        console.info('Succeeded in loading content.');
      });
    });
  }

  onWindowStageDestroy(): void {
    console.info('EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    console.info('EntryAbility onForeground');
  }

  onBackground(): void {
    console.info('EntryAbility onBackground');
  }
}
