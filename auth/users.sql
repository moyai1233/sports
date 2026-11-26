-- 회원 테이블 (회의록 3: user_id, user_password)
CREATE DATABASE IF NOT EXISTS sports_db DEFAULT CHARACTER SET utf8mb4;
USE sports_db;

CREATE TABLE IF NOT EXISTS users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  user_id       VARCHAR(20)  NOT NULL UNIQUE,   -- 로그인 아이디
  user_password VARCHAR(255) NOT NULL,          -- password_hash() 결과
  role          ENUM('user','admin') NOT NULL DEFAULT 'user',  -- 권한
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 이미 users 테이블을 만들었다면 위 대신 이것만 실행
-- ALTER TABLE users ADD COLUMN role ENUM('user','admin') NOT NULL DEFAULT 'user';

-- 어드민 지정: 먼저 회원가입 화면에서 평범하게 가입한 뒤, 그 아이디를 어드민으로 변경
-- UPDATE users SET role = 'admin' WHERE user_id = '어드민으로_쓸_아이디';
