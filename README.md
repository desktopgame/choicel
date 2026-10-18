# choicel

自然言語のキーワードから、今のEmacsで使えるコマンドとキーバインドを探すパッケージです。候補の操作は実行せず、ヘルプを開きます。

APIなしのキーワード検索に加え、任意のSystem Oneバックエンドを利用できます。APIなしでは日本語の簡単な辞書を使い、意味理解は行いません。System Oneでは全候補を分割評価し、各組の上位候補を再評価します。候補の操作は自動実行しません。

## 初めて試す

Emacs 27.1以降が対象です。ローカルではEmacs 31.1で17件のERTテストと警告なしのバイトコンパイル、Diredでのキー取得を確認しました。27.1での実行は未確認です。追加パッケージは不要です。

1. Emacsで `C-x C-f` を押し、このフォルダの `choicel.el` を開きます。
2. `M-:` で `(add-to-list 'load-path "C:/Users/dansaka/Work/Repository/choicel")` を入力してEnterを押し、次に `M-x eval-buffer` を実行します。別ファイルの辞書とSystem One機能も読み込まれます。
3. `C-x b` で普段のバッファへ移動します。
4. `M-x choicel` と入力してEnterを押します。
5. `ウィンドウを左右に分割したい` または `split window` を入力します。

`C-x` はCtrlを押しながらx、`M-x` は通常Altを押しながらxです。Altが使えないときはEscを押してからxでも入力できます。途中で困ったら `C-g` で操作をキャンセルできます。「バッファ」はEmacsで開いている文書や画面の単位です。

結果では上下キーで行を選び、`RET`（Enter）で説明を開きます。`g` で再検索、`q` で結果を閉じます。キー欄の `—` はその時点でキーが見つからないことを示します。Diredのキーを調べたい場合はDiredの画面で検索を始めてください。モードやキー設定を変えたら `g` で再検索します。

読み込み済みのコマンドと、Emacsに起動用の定義（autoload）が登録されたコマンドが対象です。検索時にパッケージは読み込みません。インストール済みでもEmacsに登録されていないパッケージは対象外です。検索は一致語と少数の用途別ヒントによる加点方式で、関連性や唯一の正解を保証するものではありません。

例えば `gitを開きたい` では、登録されていれば `magit-status`、標準機能では `vc-dir` を優先します。`ディレクトリ一覧を開きたい` や `フォルダを開きたい` では `dired` を優先します。Magitそのものをインストールする機能はありません。

## 毎回読み込む設定

動作を試した後、Emacsの設定ファイル `~/.emacs.d/init.el` に次を追加します。既存の設定は消さず、末尾などに追加してください。この `init.el` は本リポジトリの仕様書 `init.md` とは別物です。

```elisp
(add-to-list 'load-path "C:/Users/dansaka/Work/Repository/choicel")
(require 'choicel)
(global-set-key (kbd "C-c ?") #'choicel)
```

`load-path` はパッケージを探すフォルダの一覧、`require` はパッケージの読み込みです。設定後はEmacsを再起動するか、追加した式の閉じ括弧の直後で `C-x C-e` を押して一つずつ実行します。`C-c ?` はCtrl+cの後に?です。

結果の件数は `(setq choicel-max-results 20)` で変更できます。

## 辞書の編集

辞書は `choicel-dictionary.el` に分離しています。検索処理を変更せず、2つのリストを編集できます。

- `choicel-synonyms`: 表現と検索用英単語の対応。例えば `("履歴" . "history log")` をリスト内に追加します。
- `choicel-intent-hints`: 表現と優先するコマンドの対応。例えば `("履歴" . (magit-log-current vc-print-log))` をリスト内に追加します。左側はEmacsの正規表現、右側は優先順です。存在しないコマンドは候補に追加されません。

編集後は保存してください。既に読み込み済みの場合、変更した `defcustom` の定義内で `C-M-x`（Ctrl+Alt+x）を押すと現在の値も更新できます。通常の `eval-buffer` だけでは `defcustom` の既存値は更新されません。その後 `M-x choicel` で検索し直します。

個人用の追加は、辞書を変更せず、設定ファイルの `(require 'choicel)` より後ろに書くこともできます。

```elisp
(add-to-list 'choicel-synonyms '("履歴" . "history log"))
(add-to-list 'choicel-intent-hints
             '("履歴" . (magit-log-current vc-print-log)))
```

`M-x customize-group` → `choicel` からも編集・保存できます。

## 開発とデバッグの基本

`.el` はEmacs Lispのソースファイルです。ファイル末尾の `(provide 'choicel)` がパッケージ名を公開し、利用側の `(require 'choicel)` がそれを読み込みます。先頭の `lexical-binding: t` は変数の扱いを明確にする設定です。公開関数は `choicel-`、内部関数は `choicel--` で始めています。

編集したら保存して `M-x eval-buffer` で再読み込みし、もう一度検索します。`require` は読み込み済みのファイルを再評価しないので、開発中の更新には `eval-buffer` を使ってください。

- エラーの原因を表示するには `M-x toggle-debug-on-error` を有効にして再現します。出た `*Backtrace*` に呼び出し履歴が表示されます。同じ操作で無効に戻せます。
- メッセージの履歴は `C-h e`、関数の説明は `C-h f`、変数の説明は `C-h v` で確認できます。
- 関数を一行ずつ追いたい場合は、その関数の定義内で `C-u C-M-x` を押します（Edebug）。関数を使うと停止し、スペースで進めます。通常の `eval-buffer` で定義を読み直すと解除できます。
- 構文の括弧を確認するには `M-x check-parens`、コンパイル時の警告は `M-x byte-compile-file` で調べます。

## テスト

ERTはEmacsに標準搭載されたテスト機能です。Emacsで本体を読み込み、`M-x load-file` で `test/choicel-test.el` を読み込み、`M-x ert` → `t` → Enterで実行できます。

PowerShellから設定の影響を除いて実行する場合は、リポジトリのフォルダで次を使います。`emacs` が見つからなければ実行ファイルのフルパスに置き換えます。

```powershell
emacs -Q --batch -L . -l test/choicel-test.el -l test/choicel-systemone-test.el -f ert-run-tests-batch-and-exit
```

`-Q` は個人設定を読み込まない指定です。テストではコマンド列挙、ローカルキーの優先と上書き、検索順位、日本語ヒント、結果件数、候補を実行しないことを確認します。

## System Oneの設定

接続先の種類を選ぶ必要はありません。System OneのHTTP形式に対応していればURLを指定して利用できます。通常のチャット用APIとは形式が違います。ホスト型サービスでは正確なモデルIDも指定してください。

設定はパッケージのファイルに書かず、自分の `.emacs.d/local.el` に置けます。`init.el` から `local.el` を読み込む例です。既に同じ読み込みがあれば重複して追加する必要はありません。

```elisp
(load (expand-file-name "local.el" user-emacs-directory) t t)
```

`local.el` の例（URLとモデル名は自分の接続先に合わせて変更）：

```elisp
(setq choicel-backend 'auto
      choicel-systemone-url "http://localhost:8080/v1/systemone"
      choicel-systemone-model nil
      choicel-systemone-api-key
      (lambda () (getenv "SYSTEM_ONE_API_KEY")))
```

これらはEmacs全体で参照できる変数です。`.emacs.d` 側で `setq` すると、パッケージは検索時にその値を読みます。パッケージの読み込み前でも後でも設定できます。接続情報をパッケージのリポジトリに入れる必要はありません。

キーが不要なローカルサーバーなら `choicel-systemone-api-key` は `nil` で構いません。環境変数はEmacsの起動時に引き継がれます。後からWindows側で変更した場合はEmacsを再起動するか、Emacs内で `setenv` を使って反映します。個人用 `local.el` でキー文字列を直接指定することもできますが、そのファイルを共有・コミットしないでください。パッケージはキーを保存したり、診断メッセージに表示したりしません。

- `choicel-backend`: `builtin` は通信なし、`auto` はURLがあればAPIを使用、`systemone` はAPIを試行。どちらもAPI障害時は通常検索に切り替わります。
- `choicel-systemone-chunk-size`: 1回のChoiceの候補数。初期値32。モデルの候補数・コンテキスト上限に合わせて減らしてください。
- `choicel-systemone-survivors`: 各組から残す候補数と最終結果数。初期値3。チャンクサイズ未満にします。
- `choicel-max-concurrent-requests`: 同時HTTP通信数。初期値4。サーバーでの実際の並列推論数とは異なります。
- `choicel-systemone-timeout`: リクエストごとの制限時間。初期値30秒。
- `choicel-systemone-description-length`: 送信するコマンド説明の最大文字数。初期値160。

検索中もキーワード検索の結果を表示します。`C-c C-k` でAPI検索を中止できます。`g` や新しい検索は古い通信を中止し、結果バッファを破棄した場合も中止します。`q` は画面を閉じる操作なので、通信の中止には `C-c C-k` を使ってください。

送信するのは質問、モード名、コマンド名と短い説明です。編集中の文書の内容は送信しません。全候補を評価するため、登録数によっては多数のリクエストになります。ホスト型APIの料金やレート制限は接続先の条件に従います。自動リトライは行いません。複数組の確率を直接比較せず、残った候補を次のChoiceで比較します。

API形式は2026-10-18に確認した [llama.cpp公式仕様](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md#post-v1systemone-typesafe-compatible-system-one-api) と [System One APIリファレンス](https://docs.system-one.dev/en/docs/api) に基づきます。リクエストは `state` と `questions.command`、応答は `answers.command.choice` と `probabilities` を使います。バージョン・モデルごとの制約は共通ではないため、設定値を接続先に合わせてください。

ローカルの模擬APIに対する実HTTP通信、日本語とBearerヘッダーの送信、非同期集約、重複コールバック、キャンセル、タイムアウト、壊れた応答、通常検索への切り替えを検証しています。実モデルに対する接続・検索精度・速度は未検証です。HTTPの検証は `python test/http-smoke.py` で実行できます。

## 次の開発段階

実際のSystem One接続先で、候補数・通過数を調整し、精度・応答時間・リクエスト数を測定します。ライセンスと配布方法も未決定です。
