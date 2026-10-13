# 앱별 오디오와 노치 UI

## 경계

- Safari/다른 브라우저: 확장이 식별한 미디어 요소별로 재생·위치·볼륨을 제어합니다.
- 네이티브 앱: Core Audio가 등록한 실행 중인 앱을 묶어 앱 전체의 볼륨을 제어합니다. 재생 정보가 없는 항목은 볼륨 바만 표시합니다.
- `NativeAppTarget`의 bundle ID와 브라우저의 탭·프레임·미디어 ID를 구분합니다. 각 소스의 연결 상태로 그 소스의 제어만 활성화합니다.
- Apple Music의 곡 제목/재생/seek 정보는 이 오디오 경로에 아직 연결하지 않았습니다. Discord 등 통화 앱도 현재 출력 볼륨만 대상으로 합니다.

## 데이터 흐름

Core Audio 프로세스/출력 장치 변경 → `NativeAudioBridge` → EventChannel → `NativeAudioRepository` → `CombinedMediaRepository` → MediaController → 카드.

볼륨 명령 → MethodChannel → 직렬 제어 큐 → process tap + private aggregate device → 실시간 콜백에서 샘플에 gain 곱하기.

실시간 콜백은 잠금·파일 저장·메모리 할당·Flutter 호출을 하지 않습니다. 출력 gain은 10ms에 걸쳐 변경하여 갑작스러운 클릭음을 줄입니다.

## 권한과 수명

- macOS 14.2 이상. 시스템 오디오 녹음 권한과 오디오 입력 entitlement가 필요합니다.
- 자기 앱의 아주 작은 테스트 신호를 읽어 권한을 확인합니다. 오디오 파일을 저장하거나 외부로 보내지 않습니다.
- 100%로 복원하거나 앱이 종료되면 tap/aggregate를 해제하고 원래 직접 출력을 사용합니다.
- 일시정지한 앱의 원하는 볼륨은 현재 실행 동안 보관하고 재생 시작 시 다시 적용합니다. 프로세스가 사라지면 항목도 제거합니다.
- 출력 장치가 변경되면 기존 처리 경로를 해제합니다. 입력을 받지 못하는 경로는 watchdog이 해제하여 원래 출력을 복원합니다.
- 현재 처리 경로는 Float32 stereo 입력을 지원합니다. 모든 보호된 콘텐츠/특수 오디오 형식/모든 앱의 호환성을 보장하지 않습니다.

## 노치

고정 크기 AppKit 창 안에서 Flutter reveal만 애니메이션합니다. 프레임마다 창 크기나 전체 목록을 다시 계산하지 않습니다. hover 진입/이탈 범위와 160ms 이탈 지연으로 경계 흔들림을 줄였습니다. hover는 검정, 펼친 패널은 macOS 26에서 NSGlassEffectView를 사용합니다. 링크는 카드에서 숨기고 재생 위치/볼륨은 작은 캡슐 바로 표시합니다.
