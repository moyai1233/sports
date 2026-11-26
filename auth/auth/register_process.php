<?php
session_start();
require 'validate.php';

// 폼을 거치지 않은 접근 막기
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: register.php');
    exit;
}

$userId   = trim($_POST['user_id'] ?? '');
$nickname = trim($_POST['nickname'] ?? '');
$password = $_POST['user_password'] ?? '';
$confirm  = $_POST['user_password_confirm'] ?? '';

// 실패 시 오류 코드와 함께 가입 화면으로 돌려보냄 (입력했던 아이디·닉네임은 다시 채움)
function fail(string $code): void {
    global $userId, $nickname;
    $_SESSION['old_user_id']  = $userId;
    $_SESSION['old_nickname'] = $nickname;
    header('Location: register.php?error=' . $code);
    exit;
}

// 1. 입력값 검사
if ($userId === '' || $nickname === '' || $password === '') fail('empty');
if (!valid_user_id($userId)) fail('id');
if (!valid_nickname($nickname)) fail('nick');
if (strlen($password) < 8) fail('pw');
if ($password !== $confirm) fail('confirm');

try {
    require 'db.php';   // 연결 실패도 아래 catch에서 처리

    // 2. 아이디 중복 확인
    $stmt = $conn->prepare('SELECT id FROM users WHERE user_id = ?');
    $stmt->bind_param('s', $userId);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) fail('exists');

    // 3. 닉네임 중복 확인
    $stmt = $conn->prepare('SELECT id FROM users WHERE nickname = ?');
    $stmt->bind_param('s', $nickname);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) fail('nick_exists');

    // 4. 비밀번호 해시 후 저장
    $hash = password_hash($password, PASSWORD_DEFAULT);
    $stmt = $conn->prepare('INSERT INTO users (user_id, user_password, nickname) VALUES (?, ?, ?)');
    $stmt->bind_param('sss', $userId, $hash, $nickname);
    $stmt->execute();
} catch (mysqli_sql_exception $e) {
    error_log('[auth] ' . $e->getMessage());   // 원인 기록: C:\xampp\apache\logs\error.log
    // 동시에 같은 아이디/닉네임으로 가입한 경우 (UNIQUE 위반)
    if ($e->getCode() === 1062) {
        fail(str_contains($e->getMessage(), 'nickname') ? 'nick_exists' : 'exists');
    }
    fail('db');
}

// 5. 가입 완료 → 로그인 화면으로
header('Location: login.php?registered=1');
exit;
