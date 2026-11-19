<!doctype html>
<html lang="ko">

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>축구 위젯 테스트</title>
    <style>
        * {
            box-sizing: border-box
        }

        body {
            margin: 0;
            background: #f3f6f9;
            color: #14283c;
            font: 16px/1.6 system-ui, sans-serif
        }

        main {
            max-width: 1050px;
            margin: 48px auto;
            padding: 0 20px
        }

        header,
        panel {
            display: block;
            background: white;
            border: 1px solid #dce4ec;
            border-radius: 16px;
            padding: 28px;
            margin-bottom: 24px
        }

        h1 {
            margin: 0 0 8px
        }

        p {
            color: #53677a
        }

        form {
            display: flex;
            gap: 12px;
            flex-wrap: wrap
        }

        label {
            flex: 1;
            min-width: 220px
        }

        input,
        button {
            font: inherit;
            border-radius: 8px;
            padding: 11px 14px
        }

        input {
            display: block;
            width: 100%;
            border: 1px solid #a9b9c7
        }

        button {
            background: #126c57;
            color: white;
            border: 0;
            align-self: end;
            cursor: pointer
        }

        button:disabled {
            opacity: .5
        }

        small {
            color: #53677a
        }

        #status {
            min-height: 26px
        }

        a {
            color: #126c57
        }
    </style>
</head>

<body>
    <main>
        <?php $menuPrefix = './';
        require __DIR__ . '/menu.php'; ?>
    </main>
</body>

</html>