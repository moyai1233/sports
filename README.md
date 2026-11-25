# Sports

## PHP 실행

터미널에서 `sports` 폴더로 이동한 뒤 PHP 내장 서버를 실행합니다. `php -v`로 PHP가 설치되어 있는지 확인할 수 있습니다.

```sh
php -S localhost:8000
```

브라우저에서 [메인 화면](http://localhost:8000/index.php)을 열면 메뉴에서 이적료 비교, 경기 일정, 마이페이지로 이동할 수 있습니다. 서버를 종료하려면 터미널에서 `Ctrl+C`를 누릅니다.

## UI 디자인 템플릿

[UI 디자인 템플릿](./design-template.html)을 브라우저에서 열면 제목(`h1`~`h3`), 본문(`p`), 폼, 버튼, 카드, 데이터 표, 상태 배지와 알림을 확인할 수 있습니다. 다른 화면에 적용할 때는 템플릿의 마크업과 `sports.css`의 클래스를 참고하세요.

## SQL 실행 (MySQL 예시)

현재 저장소에는 SQL 스키마나 초기화 파일이 없으며, PHP 화면은 데이터베이스 없이 실행됩니다. 아래는 MySQL이 설치되어 있고 서버가 실행 중일 때 사용할 수 있는 예시입니다.

1. MySQL에 접속합니다. `root`는 사용 중인 MySQL 계정으로 바꿀 수 있습니다.

   ```sh
   mysql -u root -p
   ```

2. MySQL 프롬프트에서 데이터베이스를 만든 뒤 선택합니다.

   ```sql
   CREATE DATABASE IF NOT EXISTS sports CHARACTER SET utf8mb4;
   USE sports;
   ```

3. 별도로 준비한 `.sql` 파일을 가져오려면 MySQL 프롬프트를 `exit`로 나간 뒤 터미널에서 아래 명령을 실행합니다. `schema.sql`은 실제 SQL 파일 경로로 바꿉니다.

   ```sh
   mysql -u root -p sports < schema.sql
   ```
