# choicel

自然言語のキーワードから、今のEmacsで使えるコマンドとキーバインドを探すパッケージです。候補の操作は実行せず、ヘルプを開きます。

現在は開発の第一段階です。APIなしの検索・日本語の簡単な同義語・結果表示・ヘルプ移動を実装しています。SystemOne、非同期HTTP、全件チャンク評価は未実装です。日本語の意味理解は行いません。見つからない場合は `split window` など英語のキーワードを試してください。

## 初めて試す

Emacs 27.1以降が対象です。ローカルではEmacs 31.1で8件のERTテストと警告なしのバイトコンパイル、Diredでのキー取得を確認しました。27.1での実行は未確認です。追加パッケージは不要です。

1. Emacsで `C-x C-f` を押し、このフォルダの `choicel.el` を開きます。
2. `M-x eval-buffer` と入力してEnterを押します。ファイルの定義がEmacsに読み込まれます。
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
emacs -Q --batch -L . -l test/choicel-test.el -f ert-run-tests-batch-and-exit
```

`-Q` は個人設定を読み込まない指定です。テストではコマンド列挙、ローカルキーの優先と上書き、検索順位、日本語ヒント、結果件数、候補を実行しないことを確認します。

## 次の開発段階

SystemOneは対象のllama.cpp実装・バージョンとAPI形式を確認してから追加します。`init.md` 内のURLは暫定案なので、現在の設定には追加しないでください。ライセンスと配布方法も未決定です。
