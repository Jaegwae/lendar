# Widget Extension Scaffold

이 폴더는 `NaverCalDAVViewer` macOS 앱과 함께 붙일 `WidgetKit` 확장 스캐폴드입니다.

현재 이 작업 환경에는 `/Applications/Xcode.app`가 없어서 위젯 타깃 생성과 실행 검증은 못 했습니다. Xcode 설치 후 아래 순서로 연결하면 됩니다.

1. Xcode에서 macOS App 프로젝트를 연다.
2. `File > New > Target > Widget Extension`으로 새 타깃을 만든다.
3. 이 폴더의 `NaverCalendarWidget.swift`, `WidgetSharedSnapshot.swift`를 위젯 타깃에 추가한다.
4. 앱 타깃과 위젯 타깃에 동일한 App Group `group.calendar.naver.viewer`를 설정한다.
5. 앱에서 동기화 후 저장한 `widget-snapshot.json`을 위젯이 읽어 다가오는 일정을 표시한다.
