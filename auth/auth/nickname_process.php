<?php
session_start();
require 'validate.php';

if (!isset($_SESSION['user_no'])) {
    header('Location: login.php');
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: nickname_edit.php');
    exit;
}

$nickname = trim($_POST['nickname'] ?? '');

function fail(string $code): void {
    global $nickname;
    $_SESSION['old_nickname'] = $nickname;
    header('Location: nickname_edit.php?error=' . $code);
    exit;
}

if ($nickname === '') fail('empty');
if (!valid_nickname($nickname)) fail('nick');
if ($nickname === ($_SESSION['nickname'] ?? '')) fail('same');

try {
    require 'db.php';

    // 다른 회원이 쓰고 있는 닉네임인지 확인 (본인 제외)
    $stmt = $conn->prepare('SELECT id FROM users WHERE nickname = ? AND id <> ?');
    $stmt->bind_param('si', $nickname, $_SESSION['user_no']);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) fail('exists');

    $stmt = $conn->prepare('UPDATE users SET nickname = ? WHERE id = ?');
    $stmt->bind_param('si', $nickname, $_SESSION['user_no']);
    $stmt->execute();
} catch (mysqli_sql_exception $e) {
    error_log('[auth] ' . $e->getMessage());   // 원인 기록: C:\xampp\apache\logs\error.log
    if ($e->getCode() === 1062) fail('exists');
    fail('db');
}

$_SESSION['nickname'] = $nickname;   // 세션도 새 닉네임으로
header('Location: nickname_edit.php?done=1');
exit;
