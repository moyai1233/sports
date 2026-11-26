<!doctype html>
<html lang="ko">

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>이적료 비교</title>
    <link rel="stylesheet" href="../sports.css">
    <style>
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

        .transfer-chart {
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: 0.75rem;
            margin: 1.5rem 0 0;
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
            height: clamp(10rem, 25vw, 18rem);
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
        <p>선수와 이적 조건을 선택해 이적료를 비교하는 화면입니다.</p>

        <div class="transfer-layout">
            <section class="ui-card transfer-panel" aria-labelledby="filters-title">
                <h2 id="filters-title">검색 조건</h2>
                <form class="ui-stack">
                    <label class="ui-field">선수 이름
                        <input class="ui-input" type="search" placeholder="선수 이름을 입력하세요">
                    </label>
                    <label class="ui-field">리그
                        <select class="ui-input">
                            <option>전체 리그</option>
                            <option>프리미어리그</option>
                        </select>
                    </label>
                    <label class="ui-field">이전 구단
                        <select class="ui-input">
                            <option>전체 구단</option>
                            <option>아스널</option>
                            <option>리버풀</option>
                        </select>
                    </label>
                    <label class="ui-field">새 구단
                        <select class="ui-input">
                            <option>전체 구단</option>
                            <option>첼시</option>
                            <option>토트넘</option>
                        </select>
                    </label>
                    <label class="ui-field">포지션
                        <select class="ui-input">
                            <option>전체 포지션</option>
                            <option>공격수</option>
                            <option>미드필더</option>
                            <option>수비수</option>
                            <option>골키퍼</option>
                        </select>
                    </label>
                    <fieldset>
                        <legend>이적 연도</legend>
                        <div class="transfer-range">
                            <input class="ui-input" type="number" aria-label="이적 시작 연도" placeholder="2023">
                            <input class="ui-input" type="number" aria-label="이적 종료 연도" placeholder="2025">
                        </div>
                    </fieldset>
                    <fieldset>
                        <legend>이적료 범위 (€)</legend>
                        <div class="transfer-range">
                            <input class="ui-input" type="number" min="0" aria-label="최소 이적료" placeholder="최소">
                            <input class="ui-input" type="number" min="0" aria-label="최대 이적료" placeholder="최대">
                        </div>
                    </fieldset>
                    <fieldset>
                        <legend>이적 당시 나이</legend>
                        <div class="transfer-range">
                            <input class="ui-input" type="number" min="0" aria-label="최소 나이" placeholder="최소">
                            <input class="ui-input" type="number" min="0" aria-label="최대 나이" placeholder="최대">
                        </div>
                    </fieldset>
                    <div class="ui-actions">
                        <button class="ui-button" type="button" disabled>비교하기</button>
                        <button class="ui-button ui-button--secondary" type="reset">초기화</button>
                    </div>
                </form>
            </section>

            <section class="ui-card transfer-panel" aria-labelledby="chart-title">
                <h2 id="chart-title">선수별 이적료</h2>
                <p><span class="ui-badge">예시 데이터</span> · 단위 백만 유로</p>
                <ul class="transfer-chart">
                    <li class="transfer-column">
                        <div class="transfer-bar-track" aria-hidden="true">
                            <div class="transfer-bar" style="--bar-height: 90%; --bar-color: var(--heading)"></div>
                        </div>
                        <strong>45</strong>선수 A
                    </li>
                    <li class="transfer-column">
                        <div class="transfer-bar-track" aria-hidden="true">
                            <div class="transfer-bar" style="--bar-height: 64%; --bar-color: var(--selected)"></div>
                        </div>
                        <strong>32</strong>선수 B
                    </li>
                    <li class="transfer-column">
                        <div class="transfer-bar-track" aria-hidden="true">
                            <div class="transfer-bar" style="--bar-height: 42%; --bar-color: var(--hover)"></div>
                        </div>
                        <strong>21</strong>선수 C
                    </li>
                </ul>
            </section>
        </div>
    </main>
</body>

</html>