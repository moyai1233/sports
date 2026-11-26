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

      <p class="auth-forgot"><a href="#" id="forgot-link">비밀번호 찾기</a></p>
    </section>

    <!-- 비밀번호 찾기 창 -->
    <dialog id="forgot-dialog" class="auth-dialog">
      <div class="auth-dialog__head">
        <h2>비밀번호 찾기</h2>
        <button type="button" class="auth-dialog__close" data-close aria-label="닫기">&times;</button>
      </div>
      <p class="auth-dialog__desc">가입할 때 등록한 아이디와 닉네임을 입력하세요.</p>

      <form id="forgot-form" class="ui-stack">
        <input class="ui-input" type="text" name="user_id" placeholder="아이디를 입력하세요." maxlength="20" required>
        <input class="ui-input" type="text" name="nickname" placeholder="닉네임을 입력하세요." maxlength="12" required>
        <p id="forgot-result" class="ui-notice" hidden></p>
        <button class="ui-button auth-dialog__submit" type="submit">확인</button>
      </form>

      <button type="button" class="auth-dialog__back" data-close>로그인으로 돌아가기</button>
    </dialog>

    <script>
      const dlg    = document.getElementById('forgot-dialog');
      const form   = document.getElementById('forgot-form');
      const result = document.getElementById('forgot-result');

      // 링크 누르면 창 열기 (열 때마다 입력칸·결과 초기화)
      document.getElementById('forgot-link').addEventListener('click', (e) => {
        e.preventDefault();
        form.reset();
        result.hidden = true;
        dlg.showModal();
      });

      // X 버튼, '로그인으로 돌아가기', 창 바깥 클릭 → 닫기
      dlg.querySelectorAll('[data-close]').forEach(b => b.addEventListener('click', () => dlg.close()));
      dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.close(); });

      // 확인 → 서버에 아이디·닉네임 확인 요청, 결과를 창 안에 표시
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        let data;
        try {
          const res = await fetch('forgot_process.php', { method: 'POST', body: new FormData(form) });
          data = await res.json();
        } catch {
          data = { ok: false, message: '서버에 연결할 수 없습니다.' };
        }
        result.textContent = data.message;
        result.className = 'ui-notice ' + (data.ok ? 'ui-notice--success' : 'ui-notice--error');
        result.hidden = false;
      });
    </script>
  </main>
</body>
</html>
