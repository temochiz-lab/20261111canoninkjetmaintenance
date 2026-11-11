# Canonインクジェットプリンター 定期メンテナンス印刷

Canon PIXUS G6030 / G6000 seriesへ、指定した日数ごとにA4のカラーテストパターンを1枚印刷するWindows用プログラムです。Windowsタスクスケジューラで**毎日8:45**に起動し、前回の正常な印刷投入日からの日数を確認します。

ノズルチェックやヘッドクリーニングではありません。インク残量の取得や自動清掃は行いません。

## 必要な環境

- Windows 10 / 11、Windows PowerShell 5.1
- Canonプリンタードライバーと設定済みの印刷キュー
- A4普通紙と十分なインク
- ntfy通知を使う場合はインターネット接続と、同じtopicの購読

## 導入

1. このリポジトリをダウンロードまたはcloneします。
2. `setting.txt.sample`を`setting.txt`としてコピーし、通知先を設定します。
3. `自動印刷を設定.bat`をダブルクリックします。
4. 印刷間隔を入力します。未入力なら7日間隔です。
5. 管理者権限を許可し、表示されたプリンターを番号で選びます。
6. 最後に、設定のみなら`N`、その場で1枚印刷するなら`P`、印刷せず動作確認するなら`D`を選びます。

```powershell
Copy-Item .\setting.txt.sample .\setting.txt
notepad .\setting.txt
```

設定ファイルの例:

```text
topicname = your-ntfy-topic
pcname = your-device-name
```

`topicname`にはntfy.shで購読するtopic名を、`pcname`には通知タイトルに表示するPC名を指定します。PC名には日本語も使用できます。仮の値のままでは通知せず、ログに警告を記録します。実際のtopic名を含む`setting.txt`はGit管理対象外です。

## 印刷と通知の動作

毎日8:45（PCの現地時刻）に起動し、次の順でntfyへ通知します。

| タイミング | 通知本文 |
| --- | --- |
| 処理開始 | `Printer maintenance Start.` |
| 印刷する日 | `Today is printer test day.` |
| 印刷しない日 | `Today is no print test.` |
| 処理終了 | `Printer maintenance Exit.` |

通常の通知は、開始・日次判定・終了の3件です。通知タイトルは`pcname`です。印刷しない日は判定後に終了します。印刷履歴がない場合は、初回の実行で印刷します。

印刷APIがスプーラーへ正常投入した時点で成功とし、その日を記録します。紙の出力完了までは確認しません。例えば7日間隔なら、手動印刷が正常投入された日から7日後に次回の自動印刷を行います。

通知の送信失敗はログに残し、印刷処理を続けます。処理途中のエラーでも終了通知を試みますが、PC電源断や強制終了時には送れません。同時起動は排他ロックで制限し、重複したプロセスは通知せず終了します。

既定ではPCが起動していてログオン中である必要があります。画面ロック中は実行できます。停止中・スリープ中・ログアウト中は8:45の実行を保証できず、実行可能になってから遅れて実行される場合があります。用紙をセットし、必要に応じてCanonの設定で自動電源オンを有効にしてください。

## 設定の変更・更新

`setting.txt`を編集してから、`自動印刷を設定.bat`を再実行します。現在と同じ印刷間隔を入力し、最後に`N`を選べば、その場で印刷せずプログラムとタスクを更新できます。印刷履歴は保持されます。

インストール先は`C:\ProgramData\G6030Maintenance`、タスク名は`G6030 Periodic Maintenance Print`です。`setting.txt`はインストール先へコピーされ、再設定時に上書きされます。実行中の設定を直接変更する場合は、インストール先のファイルを編集してください。

管理者としてWindows PowerShellを開くと、時刻や間隔も指定できます。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1 -IntervalDays 7 -ScheduleTime '08:45'
```

`install.ps1`を直接実行した場合、印刷間隔の既定値は1日です。バッチ経由では7日が入力の既定値になります。スリープ解除には`-WakeComputer`、ログアウト中の実行には`-RunWhenLoggedOut`を指定します。後者はWindowsアカウントのパスワード（PINではありません）が必要です。

印刷設定はインストール先の`config.json`、通知設定は`setting.txt`に保存されます。自動タスクは`-Notify`付きで実行します。

## 手動実行

`今すぐ1枚印刷.bat`を開き、`Y`で確認すると、印刷間隔に関係なく1枚印刷します。手動印刷とdry-runでは通知しません。

印刷せずプリンターとスプーラーを確認する場合:

```powershell
& 'C:\ProgramData\G6030Maintenance\Print-G6030Maintenance.ps1' -DryRun -Force
```

実際に1枚印刷する場合:

```powershell
& 'C:\ProgramData\G6030Maintenance\Print-G6030Maintenance.ps1' -Force
```

`-Force`は印刷間隔を無視します。通常の自動運用では使用しません。失敗時の即時再試行や追加印刷は行わず、次の日次実行で再び確認します。

## ログと状態

- ログ: `C:\ProgramData\G6030Maintenance\logs\maintenance.log`
- 印刷履歴: `C:\ProgramData\G6030Maintenance\state.json`

ログはUTF-8です。`START`、`SUBMITTED`、`END`、`SKIP`、`ERROR`、`NOTIFY`を確認してください。破損した印刷履歴は日時付きバックアップへ退避します。通知は日次判定結果とプログラムの開始・終了を示し、印刷成功の保証ではありません。

## アンインストール

管理者PowerShellで、タスクだけを削除します（設定・ログは保持）。

```powershell
& 'C:\ProgramData\G6030Maintenance\uninstall.ps1'
```

プログラム・設定・ログも削除する場合:

```powershell
& 'C:\ProgramData\G6030Maintenance\uninstall.ps1' -RemoveFiles
```

Canonプリンタードライバーは変更しません。

## 検証について

スクリプト構文と、モックを用いた通知本文・通知順序・送信失敗時の処理を確認しています。実機での印刷、スリープ解除、ログアウト中の実行、自動電源オンは使用環境で確認してください。

## ライセンス

MIT License。詳細は[LICENSE](LICENSE)を参照してください。
