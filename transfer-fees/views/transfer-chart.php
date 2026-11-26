<?php

// 검색 페이지에서 받은 결과와 조건을 사용해 차트를 출력합니다.
function renderTransferChart(array $transferSearch, string $filterError, bool $hasFilters): void
{
    $matches = $transferSearch['matches'];
    $maxFee = 0;
    foreach ($matches as $record) {
        // 빈 금액은 최대값 계산에서 제외합니다.
        if (is_numeric($record['transfer_fee'])) {
            $maxFee = max($maxFee, (float) $record['transfer_fee']);
        }
    }
?>
    <section class="ui-card transfer-panel" aria-labelledby="chart-title">
        <h2 id="chart-title">이적 기록별 이적료</h2>
        <?php if ($transferSearch['columns'] === null): ?>
            <p>이적료 데이터를 읽을 수 없어 그래프를 표시할 수 없습니다.</p>
        <?php elseif ($filterError !== ''): ?>
            <p>검색 조건을 확인해 주세요.</p>
        <?php elseif (!$hasFilters): ?>
            <p>선수 이름, 구단, 이적 연도, 이적료 범위로 검색할 수 있습니다.</p>
        <?php elseif ($matches === []): ?>
            <p>검색 조건과 일치하는 이적 기록이 없습니다.</p>
        <?php else: ?>
            <p>단위는 유로(€)입니다. 금액 정보가 없는 기록은 미공개로 표시합니다.</p>
            <div class="transfer-chart-layout">
                <div class="transfer-axis" aria-hidden="true">
                    <?php if ($maxFee > 0): ?>
                        <?php // 막대와 같은 최대 금액을 4등분해 왼쪽 눈금을 표시합니다. ?>
                        <?php for ($tick = 4; $tick > 0; $tick--): ?>
                            <span>€<?= number_format($maxFee * $tick / 4, $maxFee < 4 ? 2 : 0) ?></span>
                        <?php endfor; ?>
                    <?php endif; ?>
                    <span>€0</span>
                </div>
                <ul class="transfer-chart" aria-label="이적료 막대그래프" tabindex="0">
                    <?php foreach ($matches as $record): ?>
                        <?php
                        $fee = is_numeric($record['transfer_fee']) ? (float) $record['transfer_fee'] : null;
                        // 가장 큰 금액을 100%로 두고, 최대 금액이 0이면 나누지 않습니다.
                        $height = $fee !== null && $maxFee > 0 ? max(0, $fee / $maxFee * 100) : 0;
                        $route = $record['from_club_name'] . ' → ' . $record['to_club_name'];
                        ?>
                        <li class="transfer-column">
                            <div class="transfer-bar-track" aria-hidden="true">
                                <?php if ($fee !== null): ?>
                                    <div class="transfer-bar" style="--bar-height: <?= $height ?>%; --bar-color: var(--heading)"></div>
                                <?php endif; ?>
                            </div>
                            <strong><?= $fee === null ? '미공개' : '€' . number_format($fee) ?></strong>
                            <div><?= htmlspecialchars($record['player_name'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?></div>
                            <small><?= htmlspecialchars($record['transfer_date'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?><br>
                                <?= htmlspecialchars($route, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?></small>
                        </li>
                    <?php endforeach; ?>
                </ul>
            </div>
        <?php endif; ?>
    </section>
<?php
}
