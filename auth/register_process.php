<?php
session_start();

// 폼을 거치지 않은 접근 막기
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: register.php');
    exit;
}

$userId   = trim($_POST['user_id'] ?? '');
$password = $_POST['user_password'] ?? '';
$confirm  = $_POST['user_password_confirm'] ?? '';

// 실패 시 오류 코드와 함께 가입 화면으로 돌려보냄
function fail(string $code, string $userId = ''): void {
    $_SESSION['old_user_id'] = $userId;
    header('Location: register.php?error=' . $code);
    exit;
}

// 1. 입력값 검사
if ($userId === '' || $password === '') fail('empty', $userId);
if (!preg_match('/^[A-Za-z0-9_]{4,20}$/', $userId)) fail('id', $userId);
if (strlen($password) < 8) fail('pw', $userId);
if ($password !== $confirm) fail('confirm', $userId);

try {
    require 'db.php';   // 연결 실패도 아래 catch에서 처리

    // 2. 아이디 중복 확인
    $stmt = $conn->prepare('SELECT id FROM users WHERE user_id = ?');
    $stmt->bind_param('s', $userId);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) fail('exists', $userId);

    // 3. 비밀번호 해시 후 저장
    $hash = password_hash($password, PASSWORD_DEFAULT);
    $stmt = $conn->prepare('INSERT INTO users (user_id, user_password) VALUES (?, ?)');
    $stmt->bind_param('ss', $userId, $hash);
    $stmt->execute();
} catch (mysqli_sql_exception $e) {
    // 동시에 같은 아이디로 가입한 경우 (UNIQUE 위반)
    if ($e->getCode() === 1062) fail('exists', $userId);
    fail('db', $userId);
}

// 4. 가입 완료 → 로그인 화면으로
header('Location: login.php?registered=1');
exit;
