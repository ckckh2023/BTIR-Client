import { UploadWorkspace } from '../components/UploadWorkspace';

@Entry
@Component
struct UploadPage {
  build() { Column() { UploadWorkspace() }.width('100%').height('100%') }
}
