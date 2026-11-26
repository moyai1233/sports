<?php
require_once __DIR__ . '/includes/transfer-search.php';

[
    'filters' => $filters,
    'hasFilters' => $hasFilters,
    'filterError' => $filterError,
    'filterClubs' => $filterClubs,
    'positions' => $positions,
    'transferSearch' => $transferSearch,
    'escapedPlayerName' => $escapedPlayerName,
] = prepareTransferSearch($_GET);
?>
<!doctype html>
<html lang="ko">

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>이적료 비교</title>
    <link rel="stylesheet" href="../sports.css">
    <style>
        .transfer-reset {
            text-decoration: none;
        }

        .transfer-layout {
            display: grid;
            grid-template-columns: minmax(0, 1fr) minmax(0, 1.45fr);
            gap: 1rem;
            align-items: start;
        }

        .transfer-panel h2 {
            margin-top: 0;
        }

        .transfer-range {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 0.5rem;
        }

        .transfer-chart-layout {
            --plot-height: clamp(10rem, 25vw, 18rem);
            display: grid;
            grid-template-columns: auto minmax(0, 1fr);
            gap: 0.5rem;
            margin-top: 1.5rem;
        }

        .transfer-axis {
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            height: var(--plot-height);
            text-align: right;
            font-size: 0.75rem;
            font-variant-numeric: tabular-nums;
            white-space: nowrap;
        }

        .transfer-axis span {
            line-height: 0;
        }

        .transfer-axis span:only-child {
            margin-top: auto;
        }

        .transfer-chart {
            display: grid;
            grid-auto-flow: column;
            grid-auto-columns: minmax(9rem, 1fr);
            overflow-x: auto;
            gap: 0.75rem;
            margin: 0;
            padding: 0;
            list-style: none;
        }

        .transfer-column {
            min-width: 0;
            text-align: center;
        }

        .transfer-bar-track {
            display: flex;
            align-items: end;
            justify-content: center;
            height: var(--plot-height);
            margin-bottom: 0.5rem;
            border-bottom: 1px solid var(--text);
            background: repeating-linear-gradient(to top, var(--background) 0 1px, transparent 1px 25%);
        }

        .transfer-bar {
            width: 72%;
            height: var(--bar-height);
            background: var(--bar-color);
            border-radius: 0.5rem 0.5rem 0 0;
        }

        .transfer-column strong {
            display: block;
        }

        @media (max-width: 46rem) {
            .transfer-layout {
                grid-template-columns: minmax(0, 1fr);
            }
        }
    </style>
</head>

<body>
    <?php
    $menuPrefix = '../';
    $currentPage = 'transfer-fees/transfer-fees.php';
    require __DIR__ . '/../menu.php';
    ?>
    <main class="page">
        <h1>이적료 비교</h1>
        <?php if (!$transferSearch['opened']): ?>
            <p>이적료 데이터 파일을 읽을 수 없습니다.</p>
        <?php elseif ($transferSearch['columns'] === null): ?>
            <p>이적료 데이터 파일에서 필요한 열을 찾을 수 없습니다.</p>
        <?php elseif ($filterError !== ''): ?>
            <p role="alert"><?= $filterError ?></p>
        <?php elseif ($hasFilters): ?>
            <p>
                <?php if ($filters['top'] !== ''): ?>
                    이적료 상위 <?= (int) $filters['top'] ?>건 중
                <?php else: ?>
                    검색 결과
                <?php endif; ?>
                <?= count($transferSearch['matches']) ?>건 표시
            </p>
            <?php if (!$transferSearch['players_available']): ?>
                <p>선수 정보 파일을 읽을 수 없어 포지션과 나이를 확인할 수 없습니다.</p>
            <?php endif; ?>
        <?php endif; ?>
        <p>선수와 이적 조건을 선택해 이적료를 비교하는 화면입니다.</p>

        <div class="transfer-layout">
            <section class="ui-card transfer-panel" aria-labelledby="filters-title">
                <h2 id="filters-title">검색 조건</h2>
                <form class="ui-stack" method="get" action="./transfer-fees.php">
                    <div class="ui-field">
                        <label for="transfer-player-name">선수 이름</label>
                        <input class="ui-input" type="search" id="transfer-player-name" name="player_name"
                            value="<?= $escapedPlayerName ?>" placeholder="선수 이름을 입력하세요">
                    </div>
                    <label class="ui-field">리그
                        <select class="ui-input">
                            <option>전체 리그</option>
                            <option>프리미어리그</option>
                        </select>
                    </label>
                    <?php foreach (['from_club_name' => '이전 구단', 'to_club_name' => '새 구단'] as $field => $label): ?>
                        <label class="ui-field"><?= $label ?>
                            <select class="ui-input" name="<?= $field ?>">
                                <option value="">전체 구단</option>
                                <?php foreach ($filterClubs as $club): ?>
                                    <?php $clubLabel = htmlspecialchars($club, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); ?>
                                    <option value="<?= $clubLabel ?>"<?= $filters[$field] === $club ? ' selected' : '' ?>><?= $clubLabel ?></option>
                                <?php endforeach; ?>
                            </select>
                        </label>
                    <?php endforeach; ?>
                    <label class="ui-field">포지션
                        <select class="ui-input" name="position">
                            <option value="">전체 포지션</option>
                            <?php foreach ($positions as $code => $label): ?>
                                <option value="<?= $code ?>"<?= $filters['position'] === $code ? ' selected' : '' ?>><?= $label ?></option>
                            <?php endforeach; ?>
                        </select>
                    </label>
                    <fieldset>
                        <legend>이적 연도</legend>
                        <div class="transfer-range">
                            <input class="ui-input" type="number" name="start_year" min="1000" max="9999"
                                value="<?= htmlspecialchars($filters['start_year'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>"
                                aria-label="이적 시작 연도" placeholder="2023">
                            <input class="ui-input" type="number" name="end_year" min="1000" max="9999"
                                value="<?= htmlspecialchars($filters['end_year'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>"
                                aria-label="이적 종료 연도" placeholder="2025">
                        </div>
                    </fieldset>
                    <fieldset>
                        <legend>이적료 범위 (€)</legend>
                        <div class="transfer-range">
                            <input class="ui-input" type="number" name="min_fee" min="0" step="any"
                                value="<?= htmlspecialchars($filters['min_fee'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>"
                                aria-label="최소 이적료" placeholder="최소">
                            <input class="ui-input" type="number" name="max_fee" min="0" step="any"
                                value="<?= htmlspecialchars($filters['max_fee'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>"
                                aria-label="최대 이적료" placeholder="최대">
                        </div>
                    </fieldset>
                    <fieldset>
                        <legend>이적 당시 나이</legend>
                        <div class="transfer-range">
                            <input class="ui-input" type="number" name="min_age" min="0"
                                value="<?= htmlspecialchars($filters['min_age'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>"
                                aria-label="최소 나이" placeholder="최소">
                            <input class="ui-input" type="number" name="max_age" min="0"
                                value="<?= htmlspecialchars($filters['max_age'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>"
                                aria-label="최대 나이" placeholder="최대">
                        </div>
                    </fieldset>
                    <label class="ui-field">이적료 상위 개수
                        <input class="ui-input" type="number" name="top" min="1" step="1" list="transfer-top-options"
                            value="<?= htmlspecialchars($filters['top'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>"
                            placeholder="예: 10 또는 50">
                    </label>
                    <datalist id="transfer-top-options">
                        <option value="10"></option>
                        <option value="50"></option>
                    </datalist>
                    <div class="ui-actions">
                        <button class="ui-button" type="submit">검색</button>
                        <button class="ui-button" type="submit">비교하기</button>
                        <a class="ui-button ui-button--secondary transfer-reset" href="./transfer-fees.php">초기화</a>
                    </div>
                </form>
            </section>

            <?php
            require_once __DIR__ . '/views/transfer-chart.php';
            renderTransferChart($transferSearch, $filterError, $hasFilters);
            ?>
        </div>
        <?php if ($hasFilters && $filterError === '' && $transferSearch['columns'] !== null): ?>
            <?php require __DIR__ . '/views/search-results.php'; ?>
        <?php endif; ?>
    </main>
</body>

</html>
