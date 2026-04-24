# README_AI: lendar 개발/구조 기록

이 문서는 다음 AI/개발자가 코드를 이어받을 때 빠르게 전체 의도를 파악하기 위한 상세 기록이다. 사용자용 설명은 `README.md`를 참고한다.

현재 버전: 0.2

## 프로젝트 개요

`lendar`는 macOS SwiftUI 캘린더 앱이다. 초기에는 `NaverCalDAVViewer`라는 네이버 CalDAV 전용 읽기 앱으로 시작했고, 이후 다음 요구가 반영되었다.

- 앱 이름을 `lendar`로 변경
- 네이버 CalDAV 동기화
- Google Calendar OAuth + Calendar API 동기화
- 다중 계정 연결 UI
- 캘린더별 색상 지정
- 월간 캘린더 UI/날짜별 일정 모달/일정 상세 모달
- macOS WidgetKit 위젯
- Liquid Glass 스타일과 다크 모드 대응

## 버전별 변경사항

### 0.2

- 앱 아이콘을 추가했다.
- Google OAuth와 Google Calendar API 동기화를 구현했다.
- 단일 네이버 계정 저장 구조에서 다중 계정 연결 구조로 확장했다.
- legacy Google-CalDAV metadata를 로드 시 `google` provider로 재분류하도록 보강했다.
- 설정 모달을 계정 목록 기반으로 바꿨다.
- 계정 추가는 `Google Calendar로 연결`과 `이메일 서버로 연결` 선택 단계로 나뉜다.
- Google은 OAuth 버튼으로 연결하고, 이메일 서버는 이메일/암호/서버주소 폼으로 연결한다.
- 삭제 버튼은 빨간 아이콘 버튼이며, 삭제 확인 모달을 거친다.
- 사이드바는 `caldav.calendar.naver.com` 같은 source heading 아래 캘린더 row를 보여주는 구조다.
- 캘린더 row에는 색 체크박스와 색상 palette swatch가 모두 있다.
- 초기 동기화 범위를 현재 월 기준 과거 12개월 / 미래 24개월로 줄였다.
- 먼 과거/미래 월로 이동하면 그 달 주변만 추가 동기화해 기존 데이터에 병합한다.
- CalDAV/Google 계정 fetch는 병렬화했고, provider별/캘린더별 timing diagnostics를 DEBUG 로그로 남긴다.
- 네이버 CalDAV multiget fallback에서 open-ended 반복 일정이 sync window 밖까지 무한 확장되지 않게 제한했다.
- 위젯은 앱이 저장한 snapshot만 읽도록 바뀌었다.
- 작은 창에서 UI가 망가지지 않도록 modal 크기, 월간 grid scale, window min size를 조정했다.
- 월 헤더를 Apple Calendar처럼 밝은 타이틀 영역으로 재구성했다.
- 상단 우측에 이전/오늘/다음 달 버튼을 추가했다.
- 빠른 연속 월 이동 시 scrollTo 애니메이션이 겹치지 않도록 coalescing을 넣었다.
- 스크롤로 2027년 4월 같은 현재 section window의 끝에 도달하면 다음 달 section이 이어지도록 확장 트리거를 추가했다.
- 버튼 전반에 hover/pressed 색 피드백을 추가했다.
- `README.md`는 사람용, `README_AI.md`는 AI 인수인계용으로 분리했다.

### 0.1

- 네이버 CalDAV 읽기 기반의 월간 캘린더 앱 초기 버전.
- 날짜별 일정 목록, 일정 상세, 검색, WidgetKit scaffold가 포함됐다.

## 운영 규칙

- 사용자가 명시적으로 "GitHub에 올려"라고 말하기 전까지 push하지 않는다.
- GitHub에 올리기 전에는 반드시 `client_secret*.json`, OAuth secret, Codex/OMX 상태 파일이 tracking 대상이 아닌지 확인한다.
- Google OAuth client secret은 `~/.lendar/google-oauth.json` 또는 환경변수에서만 읽어야 한다.

## 주요 파일

- `Sources/NaverCalDAVViewer/NaverCalDAVViewerApp.swift`
  - 앱 엔트리 포인트
  - `Setting > Sync Settings` 메뉴에서 `.openSyncSettings` notification 발행

- `Sources/NaverCalDAVViewer/ContentView.swift`
  - 메인 앱 UI 조립부
  - 상단 툴바, 사이드바, 모달 라우팅 포함
  - 설정/검색/일정 모달, 검색 알고리즘, 월간 레이아웃, Google OAuth/Calendar API 구현은 별도 파일로 분리됨

- `Sources/NaverCalDAVViewer/SettingsSheet.swift`
  - 연결 설정 UI
  - 계정 추가/수정/삭제, Google OAuth 시작, CalDAV 수동 입력 흐름 포함

- `Sources/NaverCalDAVViewer/SearchSheet.swift`
  - 일정 검색 모달 UI
  - 기간 필터 UI와 검색 결과 리스트 포함

- `Sources/NaverCalDAVViewer/EventSheets.swift`
  - 날짜별 일정 모달과 일정 상세 모달 UI

- `Sources/NaverCalDAVViewer/CalendarPopovers.swift`
  - 캘린더 색상 팔레트, 월 이동, compact date picker 팝오버 UI

- `Sources/NaverCalDAVViewer/CalendarViewSurfaces.swift`
  - 앱 전용 modal/input/header surface view modifier

- `Sources/NaverCalDAVViewer/CalendarStore.swift`
  - 앱 상태와 동기화 결과 반영
  - 캘린더 선택/월 이동/날짜 선택/색상 override/위젯 스냅샷 저장 트리거 담당
  - 현재 로드된 sync range 추적과 먼 달 추가 동기화 병합 담당

- `Sources/NaverCalDAVViewer/CalendarSyncService.swift`
  - 연결된 계정 배열을 순회하며 동기화
  - `provider == "google"`이면 `GoogleCalendarClient`
  - 그 외는 `CalDAVClient`
  - 계정별 실패는 전체 동기화를 망치지 않고 per-account 결과로 반환
  - 여러 계정은 병렬로 동기화하되, 결과/진단은 저장된 계정 순서대로 합침

- `Sources/NaverCalDAVViewer/CalendarSyncWindow.swift`
  - 초기 동기화 범위 제한
  - Google 반복 일정 서버 확장을 줄이기 위해 현재 월 기준 과거 12개월/미래 24개월만 요청

- `Sources/NaverCalDAVViewer/SyncTiming.swift`
  - sync phase timing helper
  - DEBUG diagnostics 및 병목 분석용

- `Sources/NaverCalDAVViewer/CalendarItemOrdering.swift`
  - 전체 일정/날짜별 일정 정렬 규칙

- `Sources/NaverCalDAVViewer/WidgetSnapshotMapper.swift`
  - 앱 `CalendarItem`을 위젯용 `WidgetEventSnapshot`으로 변환

- `Sources/NaverCalDAVViewer/GoogleOAuthCoordinator.swift`
  - Google OAuth 브라우저 인증 흐름
  - 127.0.0.1 loopback callback 서버 포함

- `Sources/NaverCalDAVViewer/GoogleCalendarClient.swift`
  - Google Calendar API 동기화
  - OAuth 설정 로딩, token refresh, calendar/event 조회 모델 포함
  - calendarList 후 각 캘린더 events 요청을 병렬화
  - `showDeleted=false`와 cancelled event filter 적용

- `Sources/NaverCalDAVViewer/ScheduleSearch.swift`
  - 검색 모달의 기간 필터와 fuzzy score 로직
  - UI 밖의 순수 로직이라 단위 테스트 대상

- `Sources/NaverCalDAVViewer/MonthLayoutBuilder.swift`
  - 월간 그리드의 month/week 생성과 event lane 배치
  - UI 밖의 순수 로직이라 단위 테스트 대상

- `Sources/NaverCalDAVViewer/SharedCalendarPalette.swift`
  - 앱과 위젯이 공유하는 캘린더 색상 코드/RGB 매핑

- `Sources/NaverCalDAVViewer/CalendarDesign.swift`
  - 앱 디자인 토큰과 adaptive color

- `Sources/NaverCalDAVViewer/CalendarBaseViewModifiers.swift`
  - 앱 공통 icon hover/glass surface/button style modifier

- `Sources/NaverCalDAVViewer/CalendarValueParser.swift`
  - iCalendar 날짜/시간 값 parser

- `Sources/NaverCalDAVViewer/CalendarFormatting.swift`
  - 앱 날짜/시간 formatter와 일정 시간 문자열

- `Sources/NaverCalDAVViewer/CalendarPalette.swift`
  - 앱 캘린더 색상 선택/표시 로직

- `Sources/NaverCalDAVViewer/CalendarText.swift`
  - CDATA cleanup, source calendar key/display helper

- `Sources/NaverCalDAVViewer/ConnectionStore.swift`
  - 계정 메타데이터 저장과 legacy migration orchestration
  - v2 다중 계정 저장 포맷 관리
  - 비밀값/공유 데이터 저장은 helper 파일로 분리됨

- `Sources/NaverCalDAVViewer/CalendarConnection.swift`
  - 저장 계정 모델

- `Sources/NaverCalDAVViewer/ConnectionNormalizer.swift`
  - 사용자명, 서버 URL, provider 판별 정규화

- `Sources/NaverCalDAVViewer/ConnectionPasswordStore.swift`
  - release Keychain / debug UserDefaults 기반 계정 비밀값 저장

- `Sources/NaverCalDAVViewer/SharedKeychainStore.swift`
  - 위젯용 스냅샷과 커스텀 색상을 shared Data Protection Keychain에 저장

- `Sources/NaverCalDAVViewer/CalDAVClient.swift`
  - Basic Auth 기반 CalDAV 클라이언트
  - 네이버 CalDAV에 사용
  - Google CalDAV는 최종적으로 쓰지 않는 방향으로 결정
  - calendar-query가 비어 있으면 multiget fallback 사용
  - 캘린더별 fetch 병렬화 및 timing diagnostics 기록

- `Sources/NaverCalDAVViewer/CalDAVPath.swift`
  - CalDAV URL/path 정규화, fallback path 생성

- `Sources/NaverCalDAVViewer/CalDAVXML.swift`
  - `XMLParser` 기반 CalDAV multistatus 응답 파싱
  - `href`, `calendar-data`, principal/home-set, calendar component metadata 추출

- `Sources/NaverCalDAVViewer/CalDAVDateFormatting.swift`
  - CalDAV UTC timestamp formatting

- `Sources/NaverCalDAVViewer/CalDAVError.swift`
  - CalDAV error 모델

- `Sources/NaverCalDAVViewer/ICSParser.swift`
  - CalDAV에서 받은 iCalendar 텍스트를 `CalendarItem`으로 변환
  - folded line, 반복 필드, `TZID`/`VALUE=DATE`, `RDATE`, `RECURRENCE-ID` override 처리
  - sync range 밖 일정은 파싱 결과에서 걸러 성능을 보호

- `Sources/NaverCalDAVViewer/ICSRecurrenceRule.swift`
  - `DAILY`/`WEEKLY`/`MONTHLY`/`YEARLY` RRULE 확장 처리
  - `WKST`, `BYDAY`, `BYMONTHDAY`, `BYMONTH`, `BYYEARDAY`, `BYWEEKNO`, `BYSETPOS` 필터 처리
  - open-ended recurrence도 요청 range 기준으로만 확장

- `Sources/NaverCalDAVViewer/Models.swift`
  - `CalendarItem`, `WidgetEventSnapshot` 등 공유 값 모델

- `Sources/NaverCalDAVViewer/MonthGridView.swift`
  - 월간 캘린더 그리드
  - 날짜 셀 클릭 시 해당 날짜 일정 리스트 모달
  - 이벤트 바 배치 및 선택 날짜 glow
  - 버튼 기반 month jump scroll과 스크롤 기반 visible month 감지 조율
  - section window 끝에 가까우면 다음/이전 달 section을 이어서 확장

- `WidgetExtension/NaverCalendarWidget.swift`
  - WidgetKit 위젯 UI
  - 오늘 일정 최대 6개 표시
  - 위젯 내부에서는 네트워크/인증을 하지 않는다

- `WidgetExtension/WidgetSharedSnapshot.swift`
  - 위젯 데이터 로더
  - 앱이 저장한 `WidgetEventSnapshot`만 읽음

## 현재 데이터 흐름

### 앱 동기화

1. 앱 시작
2. `CalendarStore.init()`
3. `restoreConnections()`
4. `scheduleInitialLoadIfPossible()`
5. `load()`
6. 초기 sync window 계산
   - 현재 월 기준 과거 12개월
   - 현재 월 기준 미래 24개월
7. 연결된 계정 배열 병렬 fetch
7. 계정별로 데이터 가져오기
   - `provider == "google"`: Google Calendar API
   - `provider == "caldav"`: CalDAV
8. 성공한 계정의 일정만 병합
9. 실패한 계정은 `connectionErrors[connection.id]`에 오류 저장
10. 성공 일정은 `items`에 반영
11. 위젯용 `WidgetEventSnapshot` 저장

### 위젯 데이터

위젯은 다음을 하지 않는다.

- CalDAV 네트워크 요청
- Google OAuth
- Keychain에서 CalDAV 비밀번호 직접 읽기

위젯은 앱이 저장한 스냅샷만 읽는다.

이렇게 바꾼 이유:

- WidgetKit extension이 직접 Keychain 비밀번호를 읽으면 macOS가 “lendar Widget이 키체인 비밀 정보를 사용하려고 합니다” 프롬프트를 반복해서 띄움
- debug 빌드는 계속 재서명되므로 `항상 허용`도 다시 깨지는 경우가 있음
- 위젯 렌더링은 짧고 안정적이어야 하므로 네트워크 호출을 피하는 것이 안전함

## 계정 모델

현재 연결은 `CalendarConnection`으로 표현한다.

필드:

- `id`
- `provider`
  - `"caldav"`
  - `"google"`
- `email`
- `password`
  - CalDAV에서는 앱 비밀번호/암호
  - Google에서는 refresh token
- `serverURL`

주의:

- `password`라는 이름은 역사적 이유로 남아 있다.
- Google provider에서는 실제 비밀번호가 아니고 refresh token이다.
- 나중에 리팩토링한다면 `secret`이나 provider별 credential enum으로 바꾸는 것이 좋다.

## 저장 구조

### UserDefaults

- 계정 metadata
- debug secret
- 커스텀 캘린더 색상 fallback

### Keychain / Data Protection Keychain

- release secret
- widget이 읽는 공유 스냅샷
- widget이 읽는 커스텀 색상

중요한 히스토리:

- debug에서 모든 계정 secret이 하나의 `naver_connection_password_debug` 키에 저장되던 버그가 있었다.
- 그 결과 Google refresh token과 Naver app password가 서로 덮어써졌다.
- 현재는 `naver_connection_password_debug.<account>` 형태로 계정별 저장한다.

## Google OAuth 구현

Google OAuth 관련 코드는 `Sources/NaverCalDAVViewer/GoogleOAuthCoordinator.swift`에 있다.

### GoogleOAuthConfig

Google OAuth 설정은 GitHub에 올리면 안 된다.

- 앱은 `~/.lendar/google-oauth.json`을 먼저 읽는다.
- 없으면 환경변수 `LENDAR_GOOGLE_CLIENT_ID`, `LENDAR_GOOGLE_CLIENT_SECRET`을 읽는다.
- 로컬 repo의 `client_secret_...json`은 `.gitignore` 대상이며 앱 코드에서 직접 fallback으로 읽지 않는다.
- scope:
  - `https://www.googleapis.com/auth/calendar.readonly`
  - `https://www.googleapis.com/auth/userinfo.email`
  - `openid`

주의:

- 공개 저장소에 client secret JSON을 올리면 안 된다.
- 이미 노출된 secret은 Google Cloud Console에서 폐기/재발급해야 한다.

### OAuthLoopbackServer

데스크톱 OAuth 콜백 수신용 로컬 HTTP 서버다.

중요한 히스토리:

- 처음에는 `localhost:<randomPort>`를 사용했다.
- Safari/Google 흐름에서 콜백이 불안정할 수 있어 `127.0.0.1`로 변경했다.
- 한때 `redirect_uri=http://127.0.0.1:0/oauth2redirect`가 나가는 버그가 있었다.
- 원인은 `NWListener.port`가 실제 시작 전 0으로 잡히는 타이밍 문제였다.
- 현재는 `53682...53692` 고정 범위에서 포트를 직접 선택하고 그 값을 redirect URI에 사용한다.

### OAuth 화면에서 사용자가 해야 하는 것

Google 테스트 앱이므로 다음이 나올 수 있다.

- “Google에서 확인되지 않은 앱”
- 권한 체크박스

권한 체크박스가 꺼져 있으면 `계속`을 눌러도 진행되지 않거나 다시 같은 화면처럼 보인다. 반드시 체크해야 한다.

## Google Calendar API 구현

`GoogleCalendarClient`는 `Sources/NaverCalDAVViewer/GoogleCalendarClient.swift`에 있다.

작동:

1. refresh token으로 access token 발급
2. `calendarList` 조회
3. 각 캘린더의 `events` 조회 (`singleEvents=true`, `showDeleted=false`)
4. `GoogleEvent`를 `CalendarItem`으로 변환
5. `status=cancelled` 이벤트는 표시 항목에서 제외

현재 이벤트 조회 범위:

- 초기 로드: 현재 월 기준 과거 12개월 / 미래 24개월
- 먼 달 이동 시: 그 달을 중심으로 추가 범위를 재요청

이유:

- UI에서 조회 개월 수 입력은 없애되, 초기 응답은 빠르게 보여야 한다.
- Google API는 `singleEvents=true`로 반복 일정을 서버에서 펼치므로 너무 넓은 범위는 응답량이 급격히 커진다.
- 네이버 CalDAV는 time-range query가 빈 결과를 주는 경우가 있어 multiget fallback이 발생하는데, 이때 범위 밖 반복 일정까지 확장하면 성능이 크게 악화된다.

## CalDAV 구현

`CalDAVClient`는 네이버 CalDAV에 사용한다.

히스토리:

- Google CalDAV도 시도했지만 Basic Auth/URL/discovery 문제가 있었다.
- Google은 OAuth + Calendar API로 가는 것이 맞다고 판단했다.
- 네이버는 앱 비밀번호 기반 CalDAV를 유지한다.

## 캘린더 source key

여러 계정을 지원하면서 같은 캘린더 이름 충돌이 생길 수 있다. 그래서 source calendar key는 다음 형태다.

```text
<source>||<calendarName>
```

관련 함수:

- `CalendarText.calendarKey(source:calendar:)`
- `CalendarText.calendarSourceName(_:)`
- `CalendarText.calendarDisplayName(_:)`

사이드바는 `calendarSourceGroups`를 사용해 source별로 묶는다.

## UI 히스토리

### 사이드바

초기에는 `내 계정`, `내 캘린더`, `구독 캘린더` 형태였다.

이후 사용자 피드백에 따라 macOS Calendar 스타일에 가까운 구조로 변경:

- `caldav.calendar.naver.com`
- 각 캘린더 row
- 왼쪽 색상 체크박스
- 오른쪽 색상 원 제거

다중 계정에서는 source별 섹션을 사용한다.

### 설정 모달

현재 구조:

- `Setting > Sync Settings`
- 연결된 계정 목록
- `+`
- 추가 모달:
  - `Google Calendar로 연결`
  - `이메일 서버로 연결`
- `이메일 서버로 연결` 선택 시 수동 CalDAV 폼 표시
- Edit은 해당 계정 수정 모달
- Delete는 확인 모달을 거친 뒤 삭제

삭제는 데이터 제거 동작이므로 자동으로 누르지 말 것.

### 월 이동 팝오버

연도 전환 피드백이 약하다는 피드백이 있었다.

현재:

- 연도 숫자에 numeric text transition
- 월 그리드는 offset/opacity 기반으로 직접 움직임
- `오늘`은 header pill 버튼

### 위젯

여러 번 디자인 수정이 있었다.

최종 방향:

- 얇은 row
- 위젯 내부에 또 큰 rounded container를 만들지 않음
- system WidgetKit background 위에 row만 배치
- 오늘 일정 최대 6개
- 캘린더명 숨김
- 날짜 위, 시간 아래
- 24시간제
- 앱에서 지정한 색상이 row left bar와 background tint에 반영

중요한 실패:

- Widget 내부 `ScrollView`와 `glassEffect` 조합은 빨간 금지 표시/렌더링 실패를 유발했다.
- 위젯 안에 큰 glass container를 넣으면 “위젯 안에 위젯”처럼 보였다.
- 현재 위젯은 안정성을 우선해 native `glassEffect`를 쓰지 않고 material/tint 기반이다.

## 다크 모드

처음에는 라이트 기준 고정 색이 많아 다크 모드에서 전체가 회색 막처럼 보였다.

수정:

- `CalendarDesign` 토큰 대부분을 adaptive color로 변경
- 다크모드에서는 일부 `glassEffect`를 material fallback으로 우회
- 이벤트 바 텍스트/배경 대비 보정

## 키체인 프롬프트 이슈

반복된 macOS Keychain 프롬프트가 있었다.

원인:

- Widget extension이 직접 credential을 읽음
- debug 빌드가 자주 재서명됨
- login keychain ACL이 계속 새 바이너리로 인식

해결 방향:

- Widget이 credential을 직접 읽지 않게 변경
- 앱이 snapshot을 저장하고 위젯은 snapshot만 읽음
- shared 데이터는 Data Protection Keychain 사용

## 검증 명령

기본 검증:

```bash
xcodebuild -project NaverCalendar.xcodeproj -scheme NaverCalendarViewer -configuration Debug -destination 'platform=macOS' build
swift build
```

앱 설치:

```bash
rm -rf /Applications/lendar.app
cp -R "/Users/jaegwan/Library/Developer/Xcode/DerivedData/NaverCalendar-ezvqryigrrgiajfdfslqexxhofzk/Build/Products/Debug/lendar.app" /Applications/lendar.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted /Applications/lendar.app
open /Applications/lendar.app
```

위젯 등록 확인:

```bash
pluginkit -m -A -p com.apple.widgetkit-extension | rg -i "lendar|calendar.naver"
```

## 남은 리스크 / 다음 작업

- Google OAuth client secret은 로컬 파일/환경변수로만 관리한다. 공개 배포 전에는 OAuth 설정/secret 배포 정책을 다시 설계해야 한다.
- 다중 Google 계정이 많아질 경우 token refresh 실패/재인증 UX를 더 정리해야 한다.
- 캘린더별 색상은 calendar source key 기반이다. 같은 계정/캘린더가 이름을 바꾸면 색상 매핑이 끊길 수 있다.
- Calendar API pagination은 구현되어 있으나 반복 이벤트/취소 이벤트 정책은 더 검토 가능.
- 위젯은 snapshot 기반이라 앱 동기화 전에는 최신 데이터를 직접 가져오지 않는다.
- 삭제 확인 모달은 SettingsSheet 내부 overlay다. 앱 전체 modal stack과 중첩될 때 zIndex를 건드릴 필요가 생길 수 있다.
