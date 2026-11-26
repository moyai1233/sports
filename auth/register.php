<?php
session_start();

// 이미 로그인한 상태면 메인으로
if (isset($_SESSION['user_id'])) {
    header('Location: index.php');
    exit;
}

// register_process.php에서 넘겨준 오류 코드 → 메시지
$messages = [
    'empty'    => '아이디와 비밀번호를 모두 입력하세요.',
    'id'       => '아이디는 영문, 숫자, _ 로 4~20자여야 합니다.',
    'pw'       => '비밀번호는 8자 이상이어야 합니다.',
    'confirm'  => '비밀번호 확인이 일치하지 않습니다.',
    'exists'   => '이미 사용 중인 아이디입니다.',
    'db'       => '서버 오류가 발생했습니다. 잠시 후 다시 시도하세요.',
];
$error = $messages[$_GET['error'] ?? ''] ?? '';

// 실패했을 때 입력했던 아이디 다시 채우기
$oldId = $_SESSION['old_user_id'] ?? '';
unset($_SESSION['old_user_id']);
?>
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>회원가입</title>
  <link rel="stylesheet" href="../css/sports.css">
  <link rel="stylesheet" href="./css/auth.css">
</head>
<body>
  <main class="page">
    <h1>회원가입</h1>

    <section class="ui-card auth-card">
      <form class="ui-stack" action="register_process.php" method="post">
        <?php if ($error): ?>
          <p class="ui-notice ui-notice--error" role="alert"><?= htmlspecialchars($error) ?></p>
        <?php endif; ?>

        <label class="ui-field">
          아이디
          <input class="ui-input" type="text" name="user_id" maxlength="20"
                 value="<?= htmlspecialchars($oldId) ?>" autocomplete="username" required>
        </label>

        <label class="ui-field">
          <span>비밀번호 <span class="ui-badge">8자 이상</span></span>
          <input class="ui-input" type="password" name="user_password" minlength="8"
                 autocomplete="new-password" required>
        </label>

        <label class="ui-field">
          비밀번호 확인
          <input class="ui-input" type="password" name="user_password_confirm" minlength="8"
                 autocomplete="new-password" required>
        </label>

        <div class="ui-actions">
          <button class="ui-button" type="submit">가입하기</button>
          <a class="ui-button ui-button--secondary" href="login.php">로그인으로</a>
        </div>
      </form>
    </section>
  </main>
</body>
</html>
