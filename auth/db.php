<?php
// ※ 임시 DB 연결 파일 (테스트용) — 최종본은 DB 담당(A)이 만든 db.php로 교체
// 접속 정보만 각자 환경에 맞게 바꿔서 사용

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT); // 오류를 예외로 받음

$DB_HOST = 'localhost';
$DB_USER = 'root';
$DB_PASS = '';
$DB_NAME = 'sports_db';

$conn = new mysqli($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME);
$conn->set_charset('utf8mb4');
