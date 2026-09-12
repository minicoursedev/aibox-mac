# AIBox Mac

Codex 藍牙閃燈與搖動開啟對話專案的 Mac 端程式庫。

## 目標流程

AI 當次回覆／輪次結束 → Mac 通知 BLE 裝置閃光 → 使用者搖動裝置 → Mac 將 Codex 帶到前景並開啟對應對話。

「完成」指當次回覆／輪次結束，不需要判斷整個任務或需求是否完成。

## 取得原始碼

```sh
git clone --recurse-submodules https://github.com/minicoursedev/aibox-mac.git
cd aibox-mac
```

已有 checkout 請先執行 `git submodule update --init --recursive`。`Sources/AIBoxCore/Remote` 引用共用的 [aibox-remote](https://github.com/minicoursedev/aibox-remote)，SSH 連線管理仍由 Mac App 負責。

## 啟動

目前使用 Swift Package 與 AppKit，需 macOS 13 以上及 Xcode／Swift 開發工具。可在 Xcode 開啟 `Package.swift` 查看程式。

在本程式庫目錄執行：

```sh
zsh scripts/build-app.sh
open build/AIBox.app
```

App 會常駐 macOS 選單列，以箱子圖示呈現。點開可查看最近 20 筆通知；點擊任一筆通知，透過 `codex://threads/<thread-id>` 開啟該筆對應的 Codex 對話。「設定」依用途分為感應、燈號、通知、裝置與 Codex 五頁；首次開啟顯示感應頁。「裝置」頁顯示實際 BLE 狀態，並提供重新連線、更換裝置與解除配對。

## BLE 與搖動

設定中的「收音敏感度」可拖曳調整 0～100：往左需更大的突發聲音才會觸發，往右更敏感。預設 50 保留原本門檻；若目前太敏感，可先往左調到 20 再按環境調整。數字不是音量百分比或分貝；0 是最低敏感度，停用收音請關閉「偵測聲音」。設定自動保存、即時同步及重連套用，需要一併更新支援 `M <敏感度>` 的 box 韌體。驗證狀態見[收音敏感度驗證紀錄](https://github.com/minicoursedev/aibox-spec/blob/main/mac-app/收音敏感度_驗證紀錄.md)。

收音調整將白色拉桿直接疊在音量條上，共用 0～100 的畫面刻度。填色代表 box 的目前收音，左右分別顯示設定值與目前音量；拖曳拉桿即可比對音量所在位置。音量高於或等於拉桿位置時立刻轉橘色，低於時恢復綠色。拖曳及新音量到達都會重新比較，沒有短暫鎖色，也不等待 box 的拍手事件。

音量每 0.1 秒更新，採用區間最大峰值；畫面數值是將 −90～0 dBFS 對映至 0～100 的相對刻度，不是環境分貝或線性振幅百分比。設定視窗顯示「感應」頁時開始回傳，切換其他分頁或關閉視窗時停止；斷線或兩秒未收到資料時清除舊音量，關閉聲音偵測時顯示已關閉。變色用於拖曳時比對目前音量，裝置的通知觸發流程沿用原有判定。

設定中的「偵測晃動」「偵測聲音」可分別開關晃動與拍手等突發聲音的通知操作，預設都開啟。設定立即傳送至已連線的 box 並等候確認；離線時先保存，重新連線後自動套用。兩者皆關閉時仍可點選通知清單。一般晃動開關不影響開機搖晃 2 秒重新配對。此功能需要支援 `S <晃動><聲音>` 的更新韌體；舊韌體拒絕指令時，App 會提示更新。

第一次啟動會開啟「選擇 AIBox」視窗，列出附近裝置。選擇一台並按「辨識這台」，box 會隨機以紅、綠、藍其中一色閃爍；顏色由 box 的亂數產生器決定，正確答案不傳給 Mac。在介面選出實體顏色，box 核對成功並保存已授權金鑰後，Mac 才儲存裝置識別碼。介面不揭露正確答案，選錯不會記住或替換原裝置，可重新辨識或另選一台。

之後啟動及重新連線只尋找已記住的裝置，不會改連其他同名 AIBox。未選擇、未完成顏色確認或斷線時，選單列箱子圖示保持紅色；完成確認並連線後恢復正常。設定中的「選擇／更換 box…」可重新選擇；取消更換會保留原選擇。配對操作集中在設定，主選單不重複提供入口。配對期間收到的通知照常保留，辨識燈號不會被通知蓋掉，搖動也不會開啟對話；確認成功後同步最新通知燈號與使用者設定。

已配對的 box 關機後，Mac 會持續搜尋原裝置；超過 30 秒仍繼續等待，box 重新開機即可自動重連。連線、握手或傳輸逾時／錯誤時，完成舊連線清理後等候 3 秒再搜尋。首次選色的搜尋仍於 30 秒停止；解除配對、配對金鑰失效、韌體或服務不符等需要人工處理的狀況不自動重試。

連線透過 CoreBluetooth 與 v5 韌體建立 LE Secure Connections Just Works 加密及 Bonding，再完成燈色確認。正常重啟沿用既有金鑰，不必每次選色。box 只允許已通過燈色確認的金鑰進行一般控制，不會因裝置名稱或位址相同就接受另一組金鑰；金鑰遺失需重新配對。macOS 可能顯示系統配對提示，請允許。

要改配其他主機，可在原 Mac 的設定按「解除 box 配對」；收到 box 清除完成回覆後，Mac 會移除所記住的裝置並停止重連。也可在 box 開機時持續搖晃 **2 秒**，強制清除舊綁定、斷開舊連線並恢復 RGB 輪亮，讓新主機重新選色配對。即使舊主機已經自動連上，這段開機手勢仍然有效，不必先關閉原 Mac。

從開機開始 IMU 取樣起，初始 2 秒保留開始手勢的機會；已開始的搖晃可跨過這段時間，繼續累積滿 2 秒。超過 300 ms 沒有動作峰值會重新計時；這是容許來回搖動低點的取樣判定。初始時間已過、主機已連線且沒有持續中的手勢時，本次開機才關閉重設偵測，後續搖晃恢復通知操作；尚未完成主機連線時則維持可重設。BLE 連線照常進行，不為此延遲連線。

Just Works 不具首次配對的中間人驗證；三選一燈色是實體裝置確認，可能撞色或猜中，不是六位數認證碼的安全等級。macOS 自己管理 BLE 系統金鑰，App 的「解除配對」不會刪除系統藍牙清單；若重新配對時系統仍使用舊金鑰而失敗，需在系統設定中忘記 AIBox 後重試。Mac 與韌體必須一起升級為 v5。

搖晃重設後若要重新連回原 Mac，App 收到重設通知或 macOS 的「裝置已移除配對資訊」錯誤，會顯示清除舊配對的說明及「開啟藍牙設定」。在系統設定對 AIBox 選擇「忘記此裝置設定」後，回到 App 按「重新搜尋」→「辨識這台」並重新確認燈色。關閉這個提示不會立即再嘗試舊配對；一般連線逾時不會被誤判為需要忘記裝置。

設定中的「交替間隔」可調整每個顏色顯示的時間：0.1～10 秒、步進 0.1 秒、預設 1 秒。回覆停止與授權請求共用這個時間，待機仍恆亮；設定自動保存，重連後同步。

預設待機時藍燈恆亮；最新待開啟通知為回覆結束時黃白交替，為授權請求時紅白交替，各色 1 秒。設定中的「燈號顏色」可點色塊開啟色環，自訂待機一色、回覆停止兩色、授權請求兩色；顏色自動儲存，重連後重新同步。每筆搖動事件開啟**最新尚未開啟的一筆**；點擊清單也會將該筆記為已開啟，後續搖動跳過。macOS 回報開啟失敗時不消耗該筆通知。開啟後改為下一筆的燈號，全部開啟後回待機色；沒有待開啟通知時搖動不動作。

顯示、記憶體與持久保存的通知紀錄都只保留最新 20 筆，依通知到達順序排列；超過上限時刪除最舊紀錄及其已開啟狀態，包含較舊尚未開啟的紀錄。連續搖動可能產生多筆事件，每筆事件最多開啟一筆，並非完整手勢辨識。

詳細分工、指令、初始參數及斷線行為見 [BLE 通訊規格](https://github.com/minicoursedev/aibox-spec/blob/main/spec/aibox-box/BLE_通訊規格.md)。

## 通知接收

建置產物包含 `AIBox.app/Contents/MacOS/aibox-notify`。需先啟動 App。主要接入方式為 `aibox-notify --hook`，由標準輸入接收官方 `Stop` 與 `PermissionRequest` JSON，保留 `session_id`、`turn_id`。Stop 讀取 `last_assistant_message`；PermissionRequest 讀取 `tool_name`、可選的 `tool_input.description`。另外接收 `PreToolUse` 中的 `request_user_input` 與 `request_user_input_async`，將 `tool_input.questions` 的 `question`／`title` 顯示為「等待回答」通知；其他工具不接收。

`Stop` 只有在 `transcript_path` 為非空字串時才加入通知及觸發燈號；欄位缺少、`null` 或 `""` 時仍回報接收成功，但不取代既有通知。`PermissionRequest` 沿用設定中的授權提醒開關，不受 `transcript_path` 影響。

設定中的「接收問答提醒（等待回答／選擇方案）」預設開啟，獨立保存於 `aibox.acceptUserInputRequests`。關閉後立即停止新增問答提醒及其燈號，既有清單與原始 payload 紀錄保留；重新啟動仍保留開關。問答提醒沿用授權請求燈色，搖動／點擊只開啟對應對話，不代答問題。這是問答工具開始前的提醒，不是持續等待狀態；異步問答時 Codex 可能繼續工作，已回答也不會自動消除提醒。此接法不涵蓋一般文字提問或 MCP 工具內部的 elicitation。

授權通知顯示「授權請求 · 工具名稱 · 原因」，點擊只開啟對應對話，不同意或拒絕授權。事件在準備請求授權時發出，不能視為持續等待人工處理的狀態。同一對話只保留最新通知，新的授權請求或 Stop 會取代該對話的先前通知，共用最多 20 筆紀錄。

Hook 接收成功後只輸出 `{}`，不回傳權限決策、停止決策或續跑指令。`Stop` 表示輪次進入停止處理；其他 hook 仍可能要求續跑，AIBox 不將它宣稱為整個任務完成。

除錯資料保存在 `~/Library/Application Support/AIBox/notification-payloads.json`，依接收順序保留最近 20 筆（舊到新），跨 App 重啟保留。同一對話的連續事件也各自保存，與選單的同對話合併規則分開。每筆包含 `receivedAt` 與原始 UTF-8 `payload` 字串，保留未解析欄位、完整工具輸入及空白；讀取 JSON 後即可還原原始 payload。檔案權限為僅目前使用者可讀寫。helper 只轉送支援且格式有效的事件；App 收到後先保存，再套用 `Stop` 過濾及通知設定，因此被過濾的 `Stop`、關閉授權提醒時收到的 `PermissionRequest` 也保留完整 payload。保存失敗會回報錯誤，不宣稱接收成功。更新前已收到的紀錄無法補回完整 payload。

仍保留舊版 notify 引數格式供相容與人工測試，不會自動把 Codex 的 notify 指向它。

以下為模擬通知測試：

```sh
build/AIBox.app/Contents/MacOS/aibox-notify '{"type":"agent-turn-complete","thread-id":"example-thread","turn-id":"example-turn","last-assistant-message":"模擬通知：接收測試"}'
```

接收程式透過同一使用者的本機 Unix socket 將資料送給 App，收到 App 確認後才成功結束。舊引數模式回報 `accepted: true`；Hook 模式輸出 `{}`。此確認只代表通知已加入清單，不代表已傳送至 BLE 裝置。

通知清單以 `aibox.completionHistory` 保存在 App 偏好設定，每次收到通知或標記已開啟時更新。保存通知內容、對話與輪次 ID、接收時間及已開啟狀態；同一對話只保留最新一筆，顯示與實際儲存上限皆為 20 筆。重新啟動後恢復清單，依最新尚未開啟的通知同步燈號；全部已開啟時使用待機燈號。此保存從新版開始生效，不從 debug payload 重播事件，先前已清空的通知與開啟狀態不會自動還原。

## 設定 Codex

點選選單列的 AIBox 箱子圖示 → `設定…` → `設定 Codex`。

- 開啟視窗時只讀取設定，顯示使用者設定檔路徑與目前狀態。
- 按鈕補加使用者層級 `hooks.Stop`、`hooks.PermissionRequest` 與限定問答工具的 `hooks.PreToolUse` 處理程式；只新增缺少的 Hook。既有 `notify`、其他 hook 與信任狀態保留。不修改 SkyComputerUseClient。
- 接著顯示 Hook 的完整命令、事件及傳入資料，供使用者選擇 `信任並啟用`。取消會保留已新增但尚未信任／啟用的 Hook，不會擅自授予信任。
- 只對使用者確認的 AIBox Hook 記錄信任；定義或設定版本改變時需重新確認。已存在相同命令時不重複新增。
- 分別顯示回覆停止、授權請求與問答提醒的設定／信任狀態，不把「已設定」當成收到真實通知。取消新增 Hook 的信任審核不會停用原本的 Hook。

依目前建置位置，寫入內容相當於：

```toml
[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "'/Users/lman/projects/aibox/aibox-mac/build/AIBox.app/Contents/MacOS/aibox-notify' --hook"

[[hooks.PermissionRequest]]
[[hooks.PermissionRequest.hooks]]
type = "command"
command = "'/Users/lman/projects/aibox/aibox-mac/build/AIBox.app/Contents/MacOS/aibox-notify' --hook"

[[hooks.PreToolUse]]
matcher = "^(request_user_input|request_user_input_async)$"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "'/Users/lman/projects/aibox/aibox-mac/build/AIBox.app/Contents/MacOS/aibox-notify' --hook"
```

設定時需已安裝提供 `codex` app-server 的 Codex 桌面 App。AIBox 透過 `codex://` 的註冊應用程式找到它；不需要 API 金鑰，也不會自動重啟 Codex。設定後重新開啟對話；若執行中的 Codex 尚未載入設定，請自行重啟 Codex，再測試新的回覆。請保持 AIBox 執行，點擊最近通知即可開啟對應對話。

請固定 App 的位置。若搬移 App，舊命令不會被本版自動刪除，需在 Codex 的 Hooks 審核介面移除或停用舊命令，再設定新路徑。

目前接入規格見 [Hooks 與點擊通知](https://github.com/minicoursedev/aibox-spec/blob/main/spec/aibox-mac/hooks_對話通知.md)。[notify 呼叫方式](https://github.com/minicoursedev/aibox-spec/blob/main/spec/aibox-mac/openai_notify_呼叫方式.md) 保留作為官方介面與歷史實作記錄，不是目前設定按鈕採用的接法。

## 遠端 SSH 通知

設定 → **遠端** 輸入已存在於 SSH 設定的主機別名（例如 `srv`），按「儲存並連線」。本版管理一台主機，沿用 SSH 金鑰及 known_hosts，不接受密碼提示、不自動信任未知主機。請先透過正常 SSH 登入完成金鑰及主機驗證。

App 在遠端建立私有 `~/.codex/aibox` 目錄並安裝 `notify.py`，透過 SSH `-R` 把該目錄的 `notify.sock` 轉送至 Mac 的 `/tmp/aibox-mac-<uid>/notify.sock`。遠端需要 Python 3.8 以上及支援 Unix socket 轉送的 OpenSSH。沒有公開 TCP 接收埠，不傳送 Mac 私鑰，也不使用 SSH agent forwarding。

第一次仍需在**遠端 Codex** 設定並信任以下命令，用於 `Stop`、`PermissionRequest`、以及 matcher 為 `^(request_user_input|request_user_input_async)$` 的 `PreToolUse`。App 不自動改寫遠端 Codex 的 Hook 設定或信任紀錄。

```sh
python3 ~/.codex/aibox/notify.py
```

若遠端版本與本機一樣使用 `config.toml` Hook 格式，需將下列項目合併到既有設定，避免重複註冊；其他版本請透過該版本的 Hook 管理流程設定相同事件及命令：

```toml
[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "python3 ~/.codex/aibox/notify.py"

[[hooks.PermissionRequest]]
[[hooks.PermissionRequest.hooks]]
type = "command"
command = "python3 ~/.codex/aibox/notify.py"

[[hooks.PreToolUse]]
matcher = "^(request_user_input|request_user_input_async)$"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "python3 ~/.codex/aibox/notify.py"
```

信任並啟用後重新開啟遠端對話。原始事件透過既有 App 通道解析、記錄及切換燈號；通知仍使用 `session_id` 開啟 `codex://threads/...`。遠端對話連結是否能在目前 Codex 版本正確開啟，需實際驗證。

連線中斷以 2、4、8…最多 30 秒間隔重試。手動斷線停止重試，並停用下次啟動時的自動連線；關閉 App 會關閉隧道。單次通知最長 4 秒後放棄，輸出 `{}`，不代替使用者核準、不要求 Codex 續跑；離線事件不補送。遠端同一帳號已有 AIBox 通道時拒絕搶占，只清理由自己持有且已失效的 socket。

「已連線」只表示隧道已建立，並不代表遠端 Hook 已設定或實體燈號已驗證。

## 測試

```sh
swift test
python3 Sources/AIBoxCore/Remote/tests/test_notify.py
```

測試涵蓋官方連字號欄位、多行中文內容、非目標事件、缺少資料及最近 20 筆的順序與計數。

另有可點擊選單動作測試，以及需明確指定本機 Codex 執行檔的整合測試：

```sh
AIBOX_TEST_CODEX_EXECUTABLE=/Applications/ChatGPT.app/Contents/Resources/codex swift test
```

整合測試使用暫存 `CODEX_HOME`，不寫入使用中的 Codex 設定。涵蓋兩種 Hook、新舊設定升級、保留 notify／其他 Hooks／註解／信任狀態、路徑引號、信任前後狀態、重複設定、版本衝突及錯誤設定檔。未指定環境變數時，11 項需本機 Codex 的測試會跳過。

裝置端程式庫位於同層的 `aibox-firmware`。

## 目前狀態

2026-09-04 已實作 PermissionRequest 接入、BLE 串接及三種燈號，42 項測試通過、0 跳過、0 失敗。設定整合測試實際使用官方 Codex RPC，但在隔離目錄執行；選單動作測試使用替身開啟器。

新版已套用固定 `build/AIBox.app` 並經使用者同意重啟、清空舊紀錄。人工 Stop → 接收程式 → AIBox → BLE 閃燈 → 實際搖動已執行，使用者確認 Codex 回到前景並開啟正確對話。

當次檢查正式設定仍只有 Stop，PermissionRequest 尚待使用者透過設定按鈕加入並審核信任。未修改既有 notify，也沒有重啟 Codex；真實 Stop／PermissionRequest 到 box 的完整流程尚未驗證。

三種燈號新版套用與實機結果見[燈號驗證紀錄](https://github.com/minicoursedev/aibox-spec/blob/main/mac-app/燈號_驗證紀錄.md)。另見 [Mac App 實作規格](https://github.com/minicoursedev/aibox-spec/blob/main/mac-app/README.md)、[BLE v1 串接驗證](https://github.com/minicoursedev/aibox-spec/blob/main/mac-app/BLE_串接驗證.md)及[較早執行紀錄](https://github.com/minicoursedev/aibox-spec/blob/main/spec/aibox-mac/執行與驗證紀錄.md)。
