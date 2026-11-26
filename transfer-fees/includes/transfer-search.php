<?php

require_once __DIR__ . '/transfer-csv.php';

// 검색 조건을 확인하고, 화면에서 사용할 검색 결과와 선택 목록을 반환합니다.
function prepareTransferSearch(array $query): array
{
    // 검색 폼에서 보낸 값은 각 입력창의 name을 키로 사용해 읽습니다.
    $filters = [];
    foreach (
        [
            'player_name',
            'from_club_name',
            'to_club_name',
            'start_year',
            'end_year',
            'min_fee',
            'max_fee',
            'position',
            'min_age',
            'max_age',
            'top'
        ] as $field
    ) {
        $value = $query[$field] ?? '';
        $filters[$field] = is_string($value) ? trim($value) : '';
    }
    $hasFilters = count(array_filter($filters, static fn($value) => $value !== '')) > 0;
    $yearError = '';
    foreach (['start_year', 'end_year'] as $field) {
        if ($filters[$field] !== '' && !preg_match('/^[1-9][0-9]{3}$/D', $filters[$field])) {
            $yearError = '이적 연도는 네 자리 숫자로 입력해 주세요.';
        }
    }
    if (
        $yearError === '' && $filters['start_year'] !== '' && $filters['end_year'] !== ''
        && (int) $filters['start_year'] > (int) $filters['end_year']
    ) {
        $yearError = '시작 연도는 종료 연도보다 늦을 수 없습니다.';
    }
    $feeError = '';
    foreach (['min_fee', 'max_fee'] as $field) {
        $fee = $filters[$field];
        // 빈칸은 범위 제한 없음이고, 0은 검색에 사용할 수 있는 금액입니다.
        if ($fee !== '' && (!is_numeric($fee) || !is_finite((float) $fee) || (float) $fee < 0)) {
            $feeError = '이적료는 0 이상의 유로 금액으로 입력해 주세요.';
            break;
        }
    }
    if (
        $feeError === '' && $filters['min_fee'] !== '' && $filters['max_fee'] !== ''
        && (float) $filters['min_fee'] > (float) $filters['max_fee']
    ) {
        $feeError = '최소 이적료는 최대 이적료보다 클 수 없습니다.';
    }
    $filterError = $yearError !== '' ? $yearError : $feeError;
    // 이전 구단과 새 구단에 같은 7개 팀을 표시합니다. 이름은 CSV 표기와 맞춥니다.
    $filterClubs = ['Arsenal', 'Chelsea', 'Liverpool', 'Man City', 'Man Utd', 'Newcastle', 'Tottenham'];
    foreach (['from_club_name', 'to_club_name'] as $field) {
        if ($filterError === '' && $filters[$field] !== '' && !in_array($filters[$field], $filterClubs, true)) {
            $filterError = '목록에 있는 구단을 선택해 주세요.';
        }
    }
    $positions = transferPositions();
    if ($filterError === '' && $filters['position'] !== '' && !isset($positions[$filters['position']])) {
        $filterError = '목록에 있는 포지션을 선택해 주세요.';
    }
    foreach (['min_age', 'max_age'] as $field) {
        if ($filterError === '' && $filters[$field] !== '' && !ctype_digit($filters[$field])) {
            $filterError = '나이는 0 이상의 정수로 입력해 주세요.';
        }
    }
    if (
        $filterError === '' && $filters['min_age'] !== '' && $filters['max_age'] !== ''
        && (int) $filters['min_age'] > (int) $filters['max_age']
    ) {
        $filterError = '최소 나이는 최대 나이보다 클 수 없습니다.';
    }
    if (
        $filterError === '' && $filters['top'] !== ''
        && filter_var($filters['top'], FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]) === false
    ) {
        $filterError = 'Top 개수는 1 이상의 정수로 입력해 주세요.';
    }
    $transferSearch = searchTransferCsv($filters, $hasFilters && $filterError === '');
    // 따옴표나 꺾쇠가 있어도 입력값을 HTML 코드로 해석하지 않도록 변환합니다.
    $escapedPlayerName = htmlspecialchars($filters['player_name'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');

    return [
        'filters' => $filters,
        'hasFilters' => $hasFilters,
        'filterError' => $filterError,
        'filterClubs' => $filterClubs,
        'positions' => $positions,
        'transferSearch' => $transferSearch,
        'escapedPlayerName' => $escapedPlayerName,
    ];
}
