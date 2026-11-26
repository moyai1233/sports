<?php
session_start();

// 이미 로그인한 상태면 메인으로
if (isset($_SESSION['user_id'])) {
    header('Location: index.php');
    exit;
}

$messages = [
    'empty' => '아이디와 비밀번호를 입력하세요.',
    'fail'  => '아이디 또는 비밀번호가 올바르지 않습니다.',
    'db'    => '서버 오류가 발생했습니다. 잠시 후 다시 시도하세요.',
];
$error = $messages[$_GET['error'] ?? ''] ?? '';
$registered = isset($_GET['registered']);

$oldId = $_SESSION['old_user_id'] ?? '';
unset($_SESSION['old_user_id']);
?>
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>로그인</title>
  <link rel="stylesheet" href="../css/sports.css">
  <link rel="stylesheet" href="./css/auth.css">
</head>
<body>
  <main class="page">
    <h1>로그인</h1>

    <section class="ui-card auth-card">
      <form class="ui-stack" action="login_process.php" method="post">
        <?php if ($registered): ?>
          <p class="ui-notice ui-notice--success">회원가입이 완료되었습니다. 로그인해 주세요.</p>
        <?php endif; ?>
        <?php if ($error): ?>
          <p class="ui-notice ui-notice--error" role="alert"><?= htmlspecialchars($error) ?></p>
        <?php endif; ?>

        <label class="ui-field">
          아이디
          <input class="ui-input" type="text" name="user_id" maxlength="20"
                 value="<?= htmlspecialchars($oldId) ?>" autocomplete="username" required>
        </label>

        <label class="ui-field">
          비밀번호
          <input class="ui-input" type="password" name="user_password"
                 autocomplete="current-password" required>
        </label>

        <div class="ui-actions">
          <button class="ui-button" type="submit">로그인</button>
          <a class="ui-button ui-button--secondary" href="register.php">회원가입</a>
        </div>
      </form>
    </section>
  </main>
</body>
</html>
