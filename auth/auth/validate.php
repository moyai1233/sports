<?php
// 아이디·닉네임 규칙 (가입, 닉네임 변경에서 함께 사용)

const USER_ID_RULE  = '아이디는 영문, 숫자, _ 로 4~20자여야 합니다.';
const NICKNAME_RULE = '닉네임은 한글, 영문, 숫자 2~12자이며 _ 는 1개까지 쓸 수 있습니다.';

function valid_user_id(string $id): bool {
    return (bool) preg_match('/^[A-Za-z0-9_]{4,20}$/', $id);
}

function valid_nickname(string $nick): bool {
    // 한글(완성형)·영문·숫자·_ 로 2~12자, _ 는 최대 1개
    return (bool) preg_match('/^[가-힣A-Za-z0-9_]{2,12}$/u', $nick)
        && substr_count($nick, '_') <= 1;
}
