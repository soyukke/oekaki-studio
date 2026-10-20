# 開発ガイド

Oekaki Studio をソースコードからビルドする人と、中のしくみを読みたい人のための文書です。アプリを使うだけなら [README](README.md) を見てください。

このリポジトリはプルリクエストを受け付けていません。更新は不定期なので、変更が必要なときはフォークして改変してください（[CONTRIBUTING.md](CONTRIBUTING.md)）。

## 必要なもの

| もの | 使いみち | 動作を確認したもの |
|---|---|---|
| Apple シリコンの Mac（macOS 14 以降） | ビルドと実行 | macOS 27.0 |
| Xcode または Command Line Tools（Swift 5.9 以降） | アプリのビルド | Swift 6.2.3 |
| [Kizu](https://github.com/kizu-lang/kizu) コンパイラ | `core/core.kizu` のビルド | main ブランチ b5687a0（2026-10-10） |
| ffmpeg（任意） | 紹介映像に音楽を重ねる | — |
| [Claude Code](https://code.claude.com/docs/ja/setup)（任意） | AI アシスタントを動かす | — |

## Kizu コンパイラを用意する

塗りつぶし（バケツ）で塗る範囲を決める処理（`core/core.kizu`）は Kizu で書かれています。`make core` でオブジェクトファイル `build/core.o` にして、Swift 側にリンクします。

C から呼び出すための機能（`export "c"` と `--emit obj`）は Kizu v0.2.4 より後に入りました。リリース版ではなく、main ブランチからビルドしたコンパイラを使ってください。ビルドの手順は Kizu の README の「Getting a Binary」にあります。

コンパイラの場所は、リポジトリの直下に `local.mk` を作って書きます。このファイルは Git に入りません。

```make
KIZU := /path/to/kizu
# 標準ライブラリを見つけられないと言われたときだけ
export KIZU_LIB_DIR := /path/to/kizu/lib/kizu
```

`make KIZU=/path/to/kizu test` のように、コマンドラインで渡すこともできます。

## よく使うコマンド

| コマンド | すること |
|---|---|
| `make run` | ビルドして起動する |
| `make test` | テストを実行する |
| `make app` | `build/OekakiStudio.app` を作る（アドホック署名） |
| `make pv` | 最初の紹介映像 `out/pv.mp4` と、その絵 `out/picture.png` を作る |
| `make logo` | ロゴとアプリアイコンを `brand/` に描き直す |
| `make clean` | ビルドで作ったものを消す |

`make clean` 以外は、先に `core/core.kizu` をビルドします。

## フォルダの構成

| 場所 | 中身 |
|---|---|
| `core/core.kizu` | 塗りつぶしで塗る範囲を決める処理（Kizu）。線の細いすき間は閉じているものとして扱い、塗りを線の下まで少し広げる |
| `Sources/COekakiCore/` | `core.o` を Swift から呼ぶための C ヘッダー |
| `Sources/OekakiKit/` | 絵のデータと処理。レイヤー、線と塗り、手順の記録と再生、案、部品、ととのえる、AI との連携。画面には依存しない |
| `Sources/OekakiApp/` | SwiftUI で作ったアプリ本体 |
| `Sources/OekakiPV/` | 作例の絵、ロゴ、紹介映像をコードで描くコマンド |
| `Tests/OekakiKitTests/` | OekakiKit のテスト |
| `brand/` | ロゴとアプリアイコン（`make logo` で作る） |
| `packaging/Info.plist` | `.app` の設定 |
| `docs/images/` | README の画像 |
| `PHILOSOPHY.md` | 設計の考え方。機能を足すときの判断の基準 |

`build/`、`.build/`、`out/` はビルドや書き出しで作られるフォルダで、Git には入りません。

## しくみの要点

- **絵は手順の積み重ね**: 線、塗り、レイヤーの操作は、すべて手順（journal）として記録します。再生、取り消し、案（branch）は、この記録をもとに動きます。
- **ファイル形式**: `.oekakistudio` は 1 つの JSON ファイルです。線は点の列として保存するので、あとから直せます。塗りと合体したレイヤーは、PNG としてファイルの中に入っています。形式の版は `Sources/OekakiKit/DocumentFile.swift` の `currentVersion` で管理しています。Finder のダブルクリックで開けるように、`packaging/Info.plist` で `dev.oekakistudio.picture` という種類として登録しています。
- **AI アシスタント**: アプリ自体はサーバーも API キーも持ちません。利用者の Mac に入っている Claude Code の `claude -p` を、キャンバスの画像（`canvas.png`）を置いた一時フォルダで実行します。AI が使える道具は、ファイルを読む `Read` だけです。くわしくは `Sources/OekakiKit/ClaudeCLI.swift` を見てください。

## 作例と紹介映像を作り直す

作例「一口食べる？」と、その紹介映像（75 秒）は、`OekakiPV` で作ります。作り直したときは、README の「作例」の表に、作った AI のモデルと時期を書き足してください。

```sh
swift build -c release --product OekakiPV
PV="$(swift build -c release --show-bin-path)/OekakiPV"

# 描いていく途中の絵、完成した絵、アプリで開ける .oekakistudio を out/bite/ に書き出す
"$PV" bite out/bite
# 色違い 3 枚
"$PV" bite out/bite 2 looks

# 映像に入れるアプリの画面を撮る
OEKAKI_SNAPSHOT="$PWD/out/bite/app/file-blur.png" OEKAKI_DEMO=file \
  OEKAKI_FILE="$PWD/out/bite/一口食べる？.oekakistudio" OEKAKI_LAYER=店 OEKAKI_LANG=ja \
  swift run OekakiApp

# 映像（音なし）と音楽を作り、重ねる
"$PV" pv out/bite/pv.mp4
"$PV" music out/bite/music.wav
ffmpeg -i out/bite/pv.mp4 -i out/bite/music.wav -c:v copy -c:a aac -b:a 192k -shortest out/bite/pv-final.mp4
```

`OekakiPV` には、ほかに次のコマンドがあります。

| コマンド | 書き出すもの |
|---|---|
| `still <png>` / `film <mp4>` / `frames <フォルダ> 秒...` | 最初の紹介映像の絵、映像、指定した秒のコマ |
| `logo <フォルダ>` / `logos <フォルダ>` | ロゴとアイコン、ロゴの案の見比べ |
| `features <フォルダ>` | 機能紹介の短い映像と静止画（Claude Code があれば本物の AI に頼む） |
| `treat <フォルダ>` | 「一口食べる？」の前の版と、その色違い |
| `night <フォルダ>` | 最初の作例の、夕方の色と夜の色 |

## 開発用の環境変数

| 変数 | 働き |
|---|---|
| `OEKAKI_LANG=ja` / `en` | 画面の言葉を固定する（ふだんは Mac の言語設定に従う） |
| `OEKAKI_CLAUDE=/path/to/claude` | `claude` コマンドの場所を指定する |
| `OEKAKI_SNAPSHOT=/path/to.png` | 起動して少ししたらウィンドウを撮って終了する |
| `OEKAKI_DEMO=...` | 撮る前に再現する場面。種類は `Sources/OekakiApp/DevSnapshot.swift` の冒頭にある |
| `OEKAKI_APPEARANCE=light` / `dark` | 外観を固定する |

`OEKAKI_DEMO=ai` は本物の Claude Code に依頼するので、ご自身の Claude のプランを使います。
