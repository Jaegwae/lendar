# lendar

버전: 0.1

macOS용 개인 캘린더 앱입니다. 네이버 CalDAV와 Google Calendar OAuth를 연결해 월간 캘린더, 날짜별 일정 목록, 일정 상세, 데스크탑 위젯을 보여줍니다.

## 주요 기능

- 월간 캘린더 보기
- 날짜 클릭 시 해당 날짜 일정 목록 표시
- 일정 클릭 시 상세 정보 표시
- 캘린더별 표시/숨김
- 캘린더별 색상 지정
- 네이버 CalDAV 계정 연결
- Google Calendar OAuth 연결
- 여러 계정 연결 관리
- macOS 데스크탑 위젯
- 다크 모드 지원
- Liquid Glass 계열 UI

## 계정 연결

`Setting > Sync Settings`에서 계정을 관리합니다.

### Google Calendar 연결

Google OAuth 설정 파일은 GitHub에 올리지 않습니다. 로컬에서 아래 위치에 OAuth JSON을 둡니다.

```text
~/.lendar/google-oauth.json
```

Google Cloud에서 받은 `client_secret_...json`을 그대로 복사해도 됩니다.

1. `+` 버튼 클릭
2. `Google Calendar로 연결` 클릭
3. 브라우저에서 Google 계정 선택
4. 경고 화면이 나오면 `계속`
5. 캘린더 읽기 권한 체크
6. `계속`

개인 테스트용 OAuth 앱이므로 Google에서 “확인되지 않은 앱” 경고가 나올 수 있습니다. 본인이 만든 Google Cloud 프로젝트라면 계속 진행하면 됩니다.

### 이메일 서버(CalDAV) 연결

1. `+` 버튼 클릭
2. `이메일 서버로 연결` 클릭
3. 이메일 주소 입력
4. 암호 입력
5. 서버 주소 입력
6. `저장 후 동기화`

네이버는 애플리케이션 비밀번호를 사용합니다.

기본 네이버 서버 주소:

```text
https://caldav.calendar.naver.com
```

## 위젯

위젯은 앱이 동기화해 저장한 일정 스냅샷을 읽습니다. 위젯 자체는 Google OAuth나 CalDAV 네트워크 요청을 직접 수행하지 않습니다. 이 구조는 macOS 키체인 경고 반복을 줄이고 WidgetKit 렌더링을 안정적으로 유지하기 위한 것입니다.

위젯에는 오늘 일정이 최대 6개까지 표시됩니다.

## 빌드

Xcode 프로젝트:

```bash
open /Users/jaegwan/Desktop/VSCODE/calendar/NaverCalendar.xcodeproj
```

명령줄 빌드:

```bash
xcodebuild -project NaverCalendar.xcodeproj -scheme NaverCalendarViewer -configuration Debug -destination 'platform=macOS' build
swift build
```

## 현재 제한

- Google Calendar는 OAuth로만 정상 연결됩니다.
- 네이버 CalDAV는 앱 비밀번호 기반으로 동작합니다.
- 위젯은 앱이 먼저 동기화한 데이터를 보여줍니다.
- 공개 배포용 앱 검증/패키징은 아직 정리하지 않았습니다.
