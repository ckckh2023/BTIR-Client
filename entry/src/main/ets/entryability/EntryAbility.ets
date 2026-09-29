import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
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
      mainWindow.setUIContent('pages/LoginPage', (err) => {
        if (err.code) {
          console.error('Failed to load content. code:' + JSON.stringify(err));
          return;
        }
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
