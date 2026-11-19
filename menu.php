<?php
$menuItems = [
    'index.php' => '홈',
    'transfer-fees/transfer-fees.php' => '이적료 비교',
    'fixtures/fixtures.php' => '경기 일정',
    'my-page/my-page.php' => '마이페이지',
];
?>
<nav class="site-nav" aria-label="주 메뉴">
    <?php foreach ($menuItems as $path => $label): ?>
        <a href="<?= $menuPrefix . $path ?>"<?= $currentPage === $path ? ' aria-current="page"' : '' ?>><?= $label ?></a>
    <?php endforeach; ?>
</nav>
