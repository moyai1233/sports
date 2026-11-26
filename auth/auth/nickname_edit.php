<?php
session_start();
require 'validate.php';

// 로그인한 사람만
if (!isset($_SESSION['user_id'])) {
    header('Location: login.php');
    exit;
}

$messages = [
    'empty'  => '새 닉네임을 입력하세요.',
    'nick'   => NICKNAME_RULE,
    'same'   => '지금 쓰고 있는 닉네임과 같습니다.',
    'exists' => '이미 사용 중인 닉네임입니다.',
    'db'     => '서버 오류가 발생했습니다. 잠시 후 다시 시도하세요.',
];
$error = $messages[$_GET['error'] ?? ''] ?? '';
$done  = isset($_GET['done']);

$oldNick = $_SESSION['old_nickname'] ?? '';
unset($_SESSION['old_nickname']);
?>
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>닉네임 변경</title>
  <link rel="stylesheet" href="../css/sports.css">
  <link rel="stylesheet" href="./css/auth.css">
</head>
<body>
  <main class="page">
    <h1>닉네임 변경</h1>

    <section class="ui-card auth-card">
      <form class="ui-stack" action="nickname_process.php" method="post">
        <?php if ($done): ?>
          <p class="ui-notice ui-notice--success">닉네임이 변경되었습니다.</p>
        <?php endif; ?>
        <?php if ($error): ?>
          <p class="ui-notice ui-notice--error" role="alert"><?= htmlspecialchars($error) ?></p>
        <?php endif; ?>

        <p>현재 닉네임: <b><?= htmlspecialchars($_SESSION['nickname'] ?? '') ?></b></p>

        <label class="ui-field">
          <span>새 닉네임 <span class="ui-badge">한글·영문·숫자 2~12자, _ 1개까지</span></span>
          <input class="ui-input" type="text" name="nickname" minlength="2" maxlength="12"
                 value="<?= htmlspecialchars($oldNick) ?>" required>
        </label>

        <div class="ui-actions">
          <button class="ui-button" type="submit">변경하기</button>
          <a class="ui-button ui-button--secondary" href="index.php">돌아가기</a>
        </div>
      </form>
    </section>
  </main>
</body>
</html>
