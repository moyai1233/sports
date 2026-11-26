-- 회원 테이블 (회의록 3: user_id, user_password)
CREATE DATABASE IF NOT EXISTS sports_db DEFAULT CHARACTER SET utf8mb4;
USE sports_db;

CREATE TABLE IF NOT EXISTS users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  user_id       VARCHAR(20)  NOT NULL UNIQUE,   -- 로그인 아이디
  user_password VARCHAR(255) NOT NULL,          -- password_hash() 결과
  nickname      VARCHAR(12)  NOT NULL UNIQUE,   -- 화면에 보이는 이름 (중복 불가)
  role          ENUM('user','admin') NOT NULL DEFAULT 'user',  -- 권한
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 어드민 지정: 먼저 회원가입 화면에서 평범하게 가입한 뒤, 그 아이디를 어드민으로 변경
-- UPDATE users SET role = 'admin' WHERE user_id = '어드민으로_쓸_아이디';


-- ─────────────────────────────────────────────────────────────
-- [이미 users 테이블이 있는 경우] 위 CREATE 대신 아래만 실행
-- 기존 회원은 아이디(앞 12자)를 임시 닉네임으로 넣음 → 로그인 후 닉네임 변경 가능
-- ─────────────────────────────────────────────────────────────
-- ALTER TABLE users ADD COLUMN nickname VARCHAR(12) NULL AFTER user_password;
-- UPDATE users SET nickname = LEFT(user_id, 12);
-- ALTER TABLE users MODIFY nickname VARCHAR(12) NOT NULL, ADD UNIQUE (nickname);
