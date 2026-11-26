<?php

function searchTransferCsv(array $filters, bool $applyFilters): array
{
    // 이 파일은 transfer-fees/includes 안에 있으므로 두 단계 올라가면 sports 폴더입니다.
    $path = __DIR__ . '/../../transfermarkt-datasets/transfers_epl7_since_2000.csv';

    // 'r'은 읽기 전용입니다. 파일을 열지 못하면 PHP 경고 대신 페이지에서 안내합니다.
    $csv = @fopen($path, 'r');
    if ($csv === false) {
        return ['opened' => false, 'columns' => null, 'matches' => []];
    }

    $columns = readTransferCsvColumns($csv);
    $matches = [];
    $players = $applyFilters && $columns !== null ? readTransferPlayers() : [];
    if ($columns !== null) {
        // 첫 줄은 이미 읽었으므로 여기서는 이적 기록을 한 줄씩 읽습니다.
        while (($row = fgetcsv($csv, escape: '')) !== false) {
            $name = $row[$columns['player_name']] ?? '';
            $fromClub = $row[$columns['from_club_name']] ?? '';
            $toClub = $row[$columns['to_club_name']] ?? '';
            $date = $row[$columns['transfer_date']] ?? '';
            $year = (int) substr($date, 0, 4);
            // 금액이 미공개인 기록은 금액 범위를 지정했을 때만 검색에서 제외합니다.
            $fee = $row[$columns['transfer_fee']] ?? '';
            // 아래 조건 중 하나라도 참이면 현재 이적 기록을 건너뜁니다.
            if (
                // 검색 전이거나 입력값이 잘못된 경우입니다.
                !$applyFilters
                // 입력한 이름이 선수명에 없으면 제외합니다. 0은 이름 맨 앞에서 찾았다는 뜻입니다.
                || ($filters['player_name'] !== '' && stripos($name, $filters['player_name']) === false)
                // 선택한 이전 구단과 기록의 이전 구단이 다르면 제외합니다.
                || ($filters['from_club_name'] !== '' && $fromClub !== $filters['from_club_name'])
                // 선택한 새 구단과 기록의 새 구단이 다르면 제외합니다.
                || ($filters['to_club_name'] !== '' && $toClub !== $filters['to_club_name'])
                // 시작 연도를 입력했으면 연도가 없거나 시작 연도보다 이전인 기록을 제외합니다.
                || ($filters['start_year'] !== '' && ($year === 0 || $year < (int) $filters['start_year']))
                // 종료 연도를 입력했으면 연도가 없거나 종료 연도보다 이후인 기록을 제외합니다.
                || ($filters['end_year'] !== '' && ($year === 0 || $year > (int) $filters['end_year']))
                // 최소 이적료를 입력했으면 금액이 없거나 최소값보다 작은 기록을 제외합니다.
                || ($filters['min_fee'] !== '' && (!is_numeric($fee) || (float) $fee < (float) $filters['min_fee']))
                // 최대 이적료를 입력했으면 금액이 없거나 최대값보다 큰 기록을 제외합니다.
                || ($filters['max_fee'] !== '' && (!is_numeric($fee) || (float) $fee > (float) $filters['max_fee']))
            ) {
                // 이 기록은 결과에 넣지 않고 CSV의 다음 기록으로 넘어갑니다.
                continue;
            }

            // 두 CSV의 player_id가 같은 선수 정보를 연결합니다.
            $player = $players[$row[$columns['player_id']] ?? ''] ?? [];
            $position = $player['position'] ?? '';
            $age = transferAge($player['date_of_birth'] ?? '', $date);
            if (($filters['position'] !== '' && $position !== $filters['position'])
                || ($filters['min_age'] !== '' && ($age === null || $age < (int) $filters['min_age']))
                || ($filters['max_age'] !== '' && ($age === null || $age > (int) $filters['max_age']))
            ) {
                continue;
            }

            // 화면에서 열 이름으로 값을 꺼낼 수 있게 저장합니다.
            $match = [];
            foreach ($columns as $columnName => $index) {
                $match[$columnName] = $row[$index] ?? '';
            }
            $match['position'] = transferPositions()[$position] ?? '정보 없음';
            $match['transfer_age'] = $age === null ? '정보 없음' : $age . '세';
            $matches[] = $match;
        }
        // 파일 끝에 도달하기 전에 읽기가 멈췄으면 일부 결과만 보여주지 않습니다.
        if (!feof($csv)) {
            fclose($csv);
            return ['opened' => false, 'columns' => null, 'matches' => []];
        }
    }

    fclose($csv);

    if ($applyFilters && $filters['top'] !== '') {
        // 다른 검색 조건을 먼저 적용한 뒤, 금액이 공개된 기록만 높은 순으로 정렬합니다.
        $matches = array_filter($matches, static fn($record) => is_numeric($record['transfer_fee']));
        usort($matches, static fn($a, $b) => (float) $b['transfer_fee'] <=> (float) $a['transfer_fee']);
        $matches = array_slice($matches, 0, (int) $filters['top']);
    }

    return [
        'opened' => true,
        'columns' => $columns,
        'matches' => $matches,
        'players_available' => $players !== null
    ];
}

function transferPositions(): array
{
    return ['Attack' => '공격수', 'Midfield' => '미드필더', 'Defender' => '수비수', 'Goalkeeper' => '골키퍼'];
}

function readTransferPlayers(): ?array
{
    $csv = @fopen(__DIR__ . '/../../transfermarkt-datasets/players.csv', 'r');
    if ($csv === false) {
        return null;
    }

    $columns = readTransferCsvColumns($csv, ['player_id', 'position', 'date_of_birth']);
    $players = [];
    if ($columns !== null) {
        while (($row = fgetcsv($csv, escape: '')) !== false) {
            $id = $row[$columns['player_id']] ?? '';
            if ($id !== '') {
                $players[$id] = [
                    'position' => $row[$columns['position']] ?? '',
                    'date_of_birth' => $row[$columns['date_of_birth']] ?? '',
                ];
            }
        }
    }
    $readComplete = $columns !== null && feof($csv);
    fclose($csv);
    return $readComplete ? $players : null;
}

function transferAge(string $birthDate, string $transferDate): ?int
{
    // 선수 CSV의 생년월일에는 시간도 들어 있으므로 날짜 부분만 사용합니다.
    $birthDate = substr($birthDate, 0, 10);
    $birth = DateTimeImmutable::createFromFormat('!Y-m-d', $birthDate);
    $transfer = DateTimeImmutable::createFromFormat('!Y-m-d', $transferDate);
    if (
        $birth === false || $transfer === false || $birth->format('Y-m-d') !== $birthDate
        || $transfer->format('Y-m-d') !== $transferDate || $transfer < $birth
    ) {
        return null;
    }
    // 연도만 빼면 생일 전에는 한 살 많아집니다. diff()는 지난 생일까지만 셉니다.
    return $birth->diff($transfer)->y;
}

function readTransferCsvColumns($csv, array $required = [
    'player_id',
    'player_name',
    'transfer_date',
    'from_club_name',
    'to_club_name',
    'transfer_fee',
]): ?array
{
    // CSV의 첫 줄은 데이터가 아니라 각 열의 이름입니다.
    $header = fgetcsv($csv, escape: '');
    if ($header === false) {
        return null;
    }

    // 고정된 위치 대신 첫 줄에서 열 이름을 검색합니다.
    $columns = [];
    foreach ($required as $name) {
        $index = array_search($name, $header, true);
        if ($index === false) {
            return null;
        }
        $columns[$name] = $index;
    }

    // 예를 들어 $columns['player_name']은 선수명 열의 위치입니다.
    return $columns;
}
