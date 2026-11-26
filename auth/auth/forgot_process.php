<?php
// 비밀번호 찾기: 아이디 + 닉네임이 같은 회원이 있는지 확인 (결과는 JSON)
// 비밀번호를 여기서 바로 바꾸지는 않음 → 닉네임은 공개 정보라 본인 확인으로 부족하기 때문
header('Content-Type: application/json; charset=utf-8');

function respond(bool $ok, string $message): void {
    echo json_encode(['ok' => $ok, 'message' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') respond(false, '잘못된 접근입니다.');

$userId   = trim($_POST['user_id'] ?? '');
$nickname = trim($_POST['nickname'] ?? '');
if ($userId === '' || $nickname === '') respond(false, '아이디와 닉네임을 모두 입력하세요.');

try {
    require 'db.php';
    $stmt = $conn->prepare('SELECT id FROM users WHERE user_id = ? AND nickname = ?');
    $stmt->bind_param('ss', $userId, $nickname);
    $stmt->execute();
    $found = $stmt->get_result()->num_rows > 0;
} catch (mysqli_sql_exception $e) {
    error_log('[auth] ' . $e->getMessage());   // 원인 기록: C:\xampp\apache\logs\error.log
    respond(false, '서버 오류가 발생했습니다. 잠시 후 다시 시도하세요.');
}

if (!$found) respond(false, '아이디와 닉네임이 일치하는 회원이 없습니다.');
respond(true, '회원 정보가 확인되었습니다. 비밀번호 재설정은 관리자에게 문의하세요.');
