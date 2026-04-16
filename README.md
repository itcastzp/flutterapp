# Flutter 图片直传 MinIO（MVP）

## 1. 准备

- 确保后端预签名服务已启动：`http://127.0.0.1:3000`
- Android 模拟器默认访问宿主机地址为 `http://10.0.2.2:3000`
- 如果是真机，修改 `lib/upload_page.dart` 中 `apiBaseUrl` 为你的服务器地址

## 2. 安装依赖

```bash
cd flutter_app
flutter pub get
```

## 3. 运行

```bash
flutter run
```

## 4. MVP 功能

- 从相册选择单张图片
- 调用后端 `/api/upload/presign`
- 通过预签名 URL 直传到 MinIO
- 展示上传进度和上传后的 object key
