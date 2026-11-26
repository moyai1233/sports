<?php
// 검색 페이지에서 넘겨준 결과가 없으면 이 뷰를 출력하지 않습니다.
if (!isset($transferSearch['matches'])) {
    return;
}

// 표에 표시할 CSV 열과 화면에 보일 제목을 같은 순서로 지정합니다.
$tableColumns = [
    'player_name' => '선수명',
    'transfer_date' => '이적일',
    'from_club_name' => '이전 구단',
    'to_club_name' => '새 구단',
    'transfer_fee' => '이적료 (€)',
    'position' => '포지션',
    'transfer_age' => '이적 당시 나이',
];
?>
<section aria-labelledby="transfer-results-title">
    <h2 id="transfer-results-title">이적 기록 검색 결과</h2>
    <?php if ($transferSearch['matches'] === []): ?>
        <p>검색 조건과 일치하는 이적 기록이 없습니다.</p>
    <?php else: ?>
        <div class="ui-table-scroll" role="region" aria-labelledby="transfer-results-title" tabindex="0">
            <table class="ui-table">
                <caption>검색된 이적 기록</caption>
                <thead>
                    <tr>
                        <?php foreach ($tableColumns as $label): ?>
                            <th scope="col"><?= $label ?></th>
                        <?php endforeach; ?>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($transferSearch['matches'] as $transfer): ?>
                        <tr>
                            <?php foreach ($tableColumns as $key => $label): ?>
                                <?php
                                $value = $transfer[$key];
                                // 빈 이적료와 실제로 0이 기록된 이적료를 구분합니다.
                                $cell = $value === '' ? ($key === 'transfer_fee' ? '미공개' : '—') : $value;
                                ?>
                                <td><?= htmlspecialchars($cell, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?></td>
                            <?php endforeach; ?>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    <?php endif; ?>
</section>
