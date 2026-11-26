<?php
session_start();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: login.php');
    exit;
}

$userId   = trim($_POST['user_id'] ?? '');
$password = $_POST['user_password'] ?? '';

function fail(string $code, string $userId = ''): void {
    $_SESSION['old_user_id'] = $userId;
    header('Location: login.php?error=' . $code);
    exit;
}

if ($userId === '' || $password === '') fail('empty', $userId);

try {
    require 'db.php';   // 연결 실패도 아래 catch에서 처리

    $stmt = $conn->prepare('SELECT id, user_password, role FROM users WHERE user_id = ?');
    $stmt->bind_param('s', $userId);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
} catch (mysqli_sql_exception $e) {
    fail('db', $userId);
}

// 아이디가 없거나 비밀번호가 틀리면 같은 메시지 (어느 쪽이 틀렸는지 알려주지 않음)
if (!$user || !password_verify($password, $user['user_password'])) {
    fail('fail', $userId);
}

// 로그인 성공: 세션 ID 새로 발급 후 로그인 정보 저장
session_regenerate_id(true);
$_SESSION['user_id'] = $userId;      // 팀 공통 규칙: 로그인 여부는 이 값으로 판단
$_SESSION['user_no'] = $user['id'];  // users.id (즐겨찾기·리뷰 테이블에서 참조용)
$_SESSION['role']    = $user['role']; // 'user' 또는 'admin'

header('Location: index.php');
exit;
