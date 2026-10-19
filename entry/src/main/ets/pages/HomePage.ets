import { UploadWorkspace } from '../components/UploadWorkspace';

@Entry
@Component
struct HomePage {
  build() { Column() { UploadWorkspace({ onHome: true }) }.width('100%').height('100%') }
}
