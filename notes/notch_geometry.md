# MacBook 노치 크기 조사와 적용 기준

확인 날짜: 2026-10-12. 단위 `pt`는 현재 화면 배율의 논리 좌표이며 물리 패널 픽셀과 다릅니다.

## 조사 결과

| 모델군 | 확인된 정보 | 앱 적용 방식 |
| --- | --- | --- |
| MacBook Pro 14인치 | NotchBay는 M1–M4 계열에서 185×32pt를 보고합니다. 이 개발 Mac(Mac17,9)에서도 현재 1512×982pt 모드에서 185×32pt를 직접 확인했습니다. | 현재 NSScreen 안전 영역에서 폭·높이·위치를 계산 |
| MacBook Pro 16인치 | 공개 관측값은 220×38pt지만 화면 설정을 구분해야 합니다. Crest는 2056×1329pt 모드에서 이 값을 실측했고, 기본 모드 값은 별도 파생값으로 구분합니다. | 고정된 220×38을 사용하지 않음 |
| MacBook Air 13인치(M2 이후) | 노치 존재는 알려져 있으나, 조사한 자료에서 모든 세대·화면 배율에 적용할 수 있는 검증된 폭·높이 표를 확인하지 못했습니다. NotchBay도 Air 수치는 보고/추정임을 명시합니다. | 실제 디스플레이 API 값으로 계산 |
| MacBook Air 15인치(M2 이후) | 위와 동일. 화면 크기나 칩만으로 논리 노치 크기를 추정하지 않습니다. | 실제 디스플레이 API 값으로 계산 |
| 노치 없는 화면 | `safeAreaInsets.top == 0` 또는 좌우 보조 영역이 없으면 하드웨어 노치로 취급하지 않습니다. | 기본은 투명하게 숨김. 상단 중앙의 작은 진입 영역과 메뉴바에서 사용 |

공개 자료는 일부 세대만 실측했고 서로 다른 화면 모드를 기본 해상도로 부르는 경우도 있습니다.
모든 MacBook에서 하드코딩한 모델표가 정확하다고 보장할 수 없으므로 **실행 중인 화면의 보고값을 기준**으로 합니다.
새 모델, 해상도/배율 변경, 디스플레이 연결 변경에도 같은 계산을 사용합니다. 모든 모델을 실기기로 검증한 것은 아닙니다.

## 계산

- 높이: `NSScreen.safeAreaInsets.top`.
- 왼쪽 끝: `auxiliaryTopLeftArea.maxX`.
- 오른쪽 끝: `auxiliaryTopRightArea.minX`.
- 폭: 오른쪽 끝 − 왼쪽 끝.
- 상단: `NSScreen.frame.maxY`.
- 노치가 있는 화면에서는 최소 폭 160pt, 최소 높이 32pt 같은 강제 보정을 사용하지 않습니다.

기존 코드는 대기 중에도 폭에 100pt, 높이에 8pt를 추가하고 양옆에 콘텐츠를 그려서 컸습니다.
이 여백을 제거했습니다. 현재 개발 Mac의 대기 창은 **185×32pt**이며 투명합니다.
포인터 진입 때만 폭을 양옆 각 50pt 늘립니다. 미리보기 높이는 하드웨어 높이 그대로입니다.
아래 스와이프를 하면 전체 목록 창이 펼쳐집니다.

투명한 대기 창에서도 포인터가 실제 노치 영역에 들어오는 것을 확인하기 위해 AppKit의
로컬/전역 mouse-moved 감지기를 사용합니다. 키보드 이벤트를 읽지 않고 위치를 기록하거나
전송하지 않습니다. 주기적인 포인터 조회 타이머는 없습니다.

측정 재현:

```sh
swift scripts/measure_notch.swift
```

현재 결과:

```text
Mac17,9
Built-in Retina Display: display 1512×982 pt, notch 185×32 pt, backing scale 2
```

## 출처

- [Apple NSScreen auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc)
- [Apple NSScreen safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)
- [Apple 전역 이벤트 감지](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)
- [NotchBay 모델별 공개 측정값](https://notchbay.com/blog/macbook-notch-size/)
- [Crest 화면 모드와 실측/파생/미검증 구분](https://crestnotch.app/macbook-notch-dimensions)

## 2026-10-13 입력·렌더링 수정

- 최신 크래시 3건(`072020`, `072331`, `072402`)은 모두 raster thread의
  `impeller::Canvas::SetupRenderPass()` null 접근이었다. Flutter 엔진 자체를 고친 것은
  아니며, 현재 macOS 앱은 `FLTEnableImpeller=false`로 해당 엔진 경로를 피한다.
  https://github.com/flutter/flutter/issues/185394
  https://github.com/flutter/website/blob/main/sites/docs/src/content/perf/impeller.md
- 매 프레임 `NSWindow.setFrame`을 호출하던 NSAnimation을 제거했다.
  렌더링 창은 420 × 최대 460 pt로 고정하고, 내부 유리와 Flutter 표시 영역만 움직인다.
  투명 여백은 화면 포인터 위치에 따라 `ignoresMouseEvents`로 클릭을 통과시킨다.
- hover는 native 화면 좌표 판정이 단독으로 담당한다. 진입 여유 8 × 6 pt,
  이탈 여유 12 × 10 pt, 이탈 지연 160 ms. 화면 경계 밖은 진입으로 처리하지 않는다.
  유휴 상태에서는 시각 요소를 노치 밖에 그리지 않는다.
- Boring Notch의 추가 hover padding, 취소 가능한 hover task, 일관된 상단 기준
  전환 원리를 조사했다. 소스 코드를 복사하지 않았다.
  https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift
- macOS 26 이상은 NSGlassEffectView, 이전 버전은 NSVisualEffectView.
  밝은 바탕에서도 콘텐츠를 읽을 수 있도록 darkAqua appearance를 지정한다.
  https://developer.apple.com/documentation/appkit/nsglasseffectview
- 카드: 단일 행 제목, 48 pt 썸네일과 seek/volume 한 행, 작은 버튼 한 행.
  긴 제목만 28 pt/s로 이동하며 시작·끝에 1.2초 휴식, 동작 줄이기에서는 정지.
  표시 목록 순서와 스크롤 컨트롤러는 기존 구조를 유지한다.
- 장시간 실행 및 모든 macOS/외부 모니터 조합에서의 안정성은 별도 검증 대상이다.

검증: analyze 경고 0, Flutter 테스트 19개 통과, macOS debug 빌드 성공.
새 빌드 실제 화면에서 카드 배치·어두운 유리 톤을 확인했고, 상단 좌표에서 native
scroll을 이용한 펼침/접기 5회 왕복이 모두 정상 동작했다. 그 구간에 새 크래시
리포트가 없었으며, 최종 빌드 plist의 FLTEnableImpeller=false를 확인했다.
