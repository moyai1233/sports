<?php
// ※ 테스트용 임시 페이지 — 로그인 상태 확인용. 메인 페이지가 생기면 삭제
session_start();
$loggedIn = isset($_SESSION['user_id']);
?>
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <title>로그인 상태 확인</title>
  <link rel="stylesheet" href="../css/sports.css">
  <link rel="stylesheet" href="./css/auth.css">
</head>
<body>
  <main class="page">
    <h1>로그인 테스트</h1>
    <section class="ui-card auth-card">
      <?php if ($loggedIn): ?>
        <p><b><?= htmlspecialchars($_SESSION['nickname'] ?? $_SESSION['user_id']) ?></b>님 로그인 중
          (아이디: <?= htmlspecialchars($_SESSION['user_id']) ?>)
          <span class="ui-badge"><?= htmlspecialchars($_SESSION['role'] ?? 'user') ?></span></p>
        <div class="ui-actions">
          <a class="ui-button" href="logout.php">로그아웃</a>
          <a class="ui-button ui-button--secondary" href="nickname_edit.php">닉네임 변경</a>
        </div>
      <?php else: ?>
        <p>로그인하지 않은 상태입니다.</p>
        <div class="ui-actions">
          <a class="ui-button" href="login.php">로그인</a>
          <a class="ui-button ui-button--secondary" href="register.php">회원가입</a>
        </div>
      <?php endif; ?>
    </section>
  </main>
</body>
</html>
