<?php
// 어드민 전용 페이지 맨 위에서 불러오기:  require __DIR__ . '/auth/admin_check.php';
// 로그인 안 했으면 로그인 화면으로, 일반 회원이면 403
if (session_status() === PHP_SESSION_NONE) session_start();

if (!isset($_SESSION['user_id'])) {
    // 이 파일(auth 폴더)의 웹 경로를 계산해서 login.php로 보냄 → 어느 폴더에서 불러도 동작
    $authUrl = str_replace('\\', '/', substr(__DIR__, strlen(realpath($_SERVER['DOCUMENT_ROOT']))));
    header('Location: ' . $authUrl . '/login.php');
    exit;
}
if (($_SESSION['role'] ?? 'user') !== 'admin') {
    http_response_code(403);
    exit('관리자만 접근할 수 있습니다.');
}
