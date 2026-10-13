# 다른 브라우저 연결 (개발용)

Safari는 macOS 앱에 포함된 확장을 사용합니다. 나머지 브라우저는 별도 WebExtension을 설치합니다.

## Chrome / Edge / Brave

1. `chrome://extensions`, `edge://extensions`, `brave://extensions`에서 개발자 모드를 켭니다.
2. **압축해제된 확장 프로그램 로드**로 이 저장소의 `extensions/chromium` 폴더를 선택합니다.
3. 확장 세부정보 → 확장 옵션을 엽니다.
4. Hankyeon 노치를 펼침 → 브라우저 연결 버튼에서 주소와 연결 코드를 복사합니다.
5. 확장 옵션에 붙여넣고 실제 브라우저 이름을 선택한 뒤 저장합니다.
6. 이미 열려 있던 미디어도 처음 연결할 때 조회합니다. 접근을 허용한 HTML video/audio가 노치 목록에 합쳐집니다.

Chromium 116 이상이 필요합니다. Arc 등 Chromium 기반 브라우저도 같은 패키지를 시도할 수 있지만 개별 호환성은 미검증입니다.

## Firefox

`about:debugging` → 이 Firefox → 임시 부가 기능 로드 → `extensions/firefox/manifest.json`을 선택합니다.
확장 옵션에서 같은 방식으로 연결합니다. 임시 설치는 브라우저 종료 시 제거되며, 정식 배포에는 Mozilla 서명이 필요합니다.

## 연결 구조와 제한

- 서버는 `127.0.0.1:43127`에서만 열립니다. 외부 네트워크에 바인딩하지 않습니다.
- Chrome/Firefox 확장 Origin만 허용하고, 앱의 256-bit 연결 코드가 일치해야 목록과 명령을 교환합니다.
- 코드는 앱의 Application Support 폴더와 브라우저 로컬 확장 설정에 보관됩니다. 로그에 출력하지 않습니다.
- 브라우저 프로필마다 clientId가 달라서 같은 tabId/frameId라도 다른 소스로 구별합니다.
- 페이지 이벤트로 변경된 탭을 조회합니다. 20초 ping은 Chromium service worker 연결 유지용이고, 미디어 조회 타이머가 아닙니다.
- app 종료 시 연결은 닫힙니다. 앱을 다시 켜면 같은 코드로 재연결합니다.
- 웹사이트 접근 권한을 허용해야 해당 문서와 iframe을 읽고 제어할 수 있습니다.
- 앱 목록 수신과 명령 ACK는 실제 loopback 소켓 테스트로 검증했습니다. Chrome/Edge/Brave/Firefox 실제 설치별 검증은 별도입니다.
- Store에 등록된 설치 패키지는 아직 없습니다. 사용자가 개발자 모드를 쓰지 않는 배포는 Chrome Web Store / Edge Add-ons / Firefox Add-ons 등록 단계가 필요합니다.

## 공통 코드 변경

Safari의 `macos/HankyeonSafariExtension/Resources/media`가 원본입니다.
브라우저별 통신 진입점은 `extensions/browser/background.js`이고,
`python3 scripts/build_browser_extension.py`가 공통 모듈을 복사하고 두 manifest를 생성합니다.
생성된 `extensions/chromium`, `extensions/firefox`에서 직접 수정하지 마세요.

Chrome 연결 수명 참고: https://developer.chrome.com/docs/extensions/how-to/web-platform/websockets
