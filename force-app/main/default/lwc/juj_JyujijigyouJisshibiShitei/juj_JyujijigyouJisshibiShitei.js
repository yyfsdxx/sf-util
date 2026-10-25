/**
 * JUJ081 従事可能日指定（JUJ080 の子コンポーネントとしてモーダル表示する）
 * 設計書：機能設計書 処理詳細（JUJ080／081／082 共通シート）
 * コメント中の番号は「1.画面アクション No.」「3.表示ラベル No.」「4.入力チェック No.」「5.データ更新 (n)」に対応する。
 * 【要確認】は QA・メタデータの確定後に修正する。
 *
 * ※ 本画面は DB を更新しない。保存時に選択した従事可能日を JUJ080 へ返却する。
 * ※ 従事可能日は時間帯単位で選択する。形式：[{ kanoubiDate: 'yyyy-MM-dd', timeSlots: [{ startTime, endTime }] }]
 *   時間帯の同一判定は「開始時間＋終了時間」で行う。
 *
 * 呼出し元（JUJ080）：
 *   <c-juj_-jyujijigyou-jisshibi-shitei jigyo-key={jigyoKey} jujisha-no={jujishaNo} kanoubi-dates={kanoubiDates}
 *             onsave={...} onclose={...}></c-juj_-jyujijigyou-jisshibi-shitei>
 * イベント：
 *   save  … 保存時。detail = { kanoubiDates }
 *   close … 閉じる時。初期表示エラーで閉じる場合は detail = { errorMessage }
 */
import { LightningElement, api, wire } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';

// ========== Apex（未デプロイのため一時的にコメントアウト。デプロイ後は import を戻し、下のスタブを削除する）==========
// import init from '@salesforce/apex/Juj_JyujijigyouJisshibiShiteiController.init';
// import getDays from '@salesforce/apex/Juj_JyujijigyouJisshibiShiteiController.getDays';
// import checkSave from '@salesforce/apex/Juj_JyujijigyouJisshibiShiteiController.checkSave';

// メッセージ【要確認 QA-20】文言・ID
const MSG = {
    NO_JISSHIBI: '実施日が登録されていません。', // No.21 実施日が1件も登録されていない場合
    CONFIRM_SAVE:
        '保存します。よろしいですか？\n※この時点では応募は確定されません。応募を確定するには元画面で登録ボタンを押下してください。', // WLP009-0004
    UNEXPECTED: '予期しないエラーが発生しました。'
};

// 行の区分（CSS クラス。3.表示ラベル No.60 の備考）
const ROW_WARIATE = 'row-status-waritate'; // 割当
const ROW_BOSHU = 'row-status-oubo'; // 募集
const CHILD_ROW = 'child-row'; // 時間帯行（統一のスタイル）
const YOUBI_SATURDAY = 'youbi-saturday';
const YOUBI_SUNDAY = 'youbi-sunday'; // 日曜・祝日
const CELL_CLIP = 'cell-clip';
const CELL_WRAP = 'cell-wrap';

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

// 項目ラベルの取得元オブジェクト（3.表示ラベルの「項目ラベル取得元」）
const JIGYO_OBJECT = 'Juji_Jigyo__c'; // 従事事業
const BASYO_OBJECT = 'Juji_Basyo_Master__c'; // 従事場所マスタ
const SODANIN_OBJECT = 'Soudanin_Master__c'; // 相談員マスタ（氏名のラベル取得元。JUJ080 と同じ）
const OFFICE_OBJECT = 'Account'; // 事務所・法人

// 画面項目 → [オブジェクト, 項目名, 既定ラベル]。ラベルはメタデータから取得し、取得できない場合は既定ラベルを表示する
// （一覧の列名はオブジェクトの項目と異なるため固定）
const LABEL_FIELDS = {
    jujiJigyoNo: [JIGYO_OBJECT, 'Juji_Juji_Jigyo_No__c', '従事事業No.'],
    jigyoName: [JIGYO_OBJECT, 'Juji_Juji_Jigyo_Name__c', '従事事業名'],
    jisiNendo: [JIGYO_OBJECT, 'Juji_Jisi_Nendo__c', '実施年度'],
    jujiBasyoNo: [BASYO_OBJECT, 'JujM_Juji_Basyo_No__c', '従事場所No.'],
    basyoName: [BASYO_OBJECT, 'JujM_Juji_Basyo_Name__c', '従事場所名'],
    shibuCode: [OFFICE_OBJECT, 'Jims_Sibu_Code__c', '支部コード'],
    shibuName: [OFFICE_OBJECT, 'Jims_Sibu_Name__c', '支部名'],
    jujishaName: [SODANIN_OBJECT, 'SouM_Sodanin_Name__c', '氏名']
};

// 項目ラベル取得元が「固定」の項目
const FIXED_LABELS = {
    jujishaNo: '登録番号/相談員番号'
};

// ========== スタブ（Apex デプロイ後に削除）==========
const init = async () => ({
    jigyo: { jigyoName: 'テスト事業', shibuCode: '001', shibuName: 'テスト支部', basyoName: 'テスト場所' },
    jujishaName: 'テスト 太郎',
    ownAssigned: [{ kanoubiDate: '2026-11-10', timeSlots: [{ startTime: '10:00', endTime: '11:00' }] }],
    minJisshibi: '2026-11-03',
    maxJisshibi: '2027-01-20'
});
const getDays = async () => [
    {
        jisshibi: '2026-11-03', boshuNinzu: 5, startTime: '09:00', endTime: '15:00', biko: '午前・午後', wariateNinzu: 1,
        timeSlots: [
            { startTime: '09:00', endTime: '12:00', count: 3, wariateNinzu: 1 },
            { startTime: '13:00', endTime: '15:00', count: 2, wariateNinzu: 0 }
        ]
    },
    {
        jisshibi: '2026-11-10', boshuNinzu: 1, startTime: '10:00', endTime: '11:00', biko: '', wariateNinzu: 0,
        timeSlots: [{ startTime: '10:00', endTime: '11:00', count: 1, wariateNinzu: 0 }]
    },
    {
        jisshibi: '2026-12-01', boshuNinzu: 2, startTime: '10:00', endTime: '16:00', biko: '', wariateNinzu: 0,
        timeSlots: [
            { startTime: '10:00', endTime: '12:00', count: 1, wariateNinzu: 0 },
            { startTime: '14:00', endTime: '16:00', count: 1, wariateNinzu: 0 }
        ]
    }
];
const checkSave = async () => {};
// ========== スタブ ここまで ==========

// ========== 日付ユーティリティ（タイムゾーンの影響を受けないよう UTC で計算する） ==========
const toDateText = (d) => d.toISOString().slice(0, 10); // 'yyyy-MM-dd'
const parseDate = (text) => new Date(`${text}T00:00:00Z`);
const firstOfMonth = (ym) => parseDate(`${ym}-01`); // ym = 'yyyy-MM'
const addMonths = (ym, n) => {
    const d = firstOfMonth(ym);
    d.setUTCMonth(d.getUTCMonth() + n);
    return toDateText(d).slice(0, 7);
};
const todayText = () => {
    const now = new Date();
    return toDateText(new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())));
};

// 時間帯の同一判定キー（開始時間＋終了時間）
const slotKey = (slot) => `${slot.startTime}-${slot.endTime}`;
const keyToSlot = (key) => {
    const [startTime, endTime] = key.split('-');
    return { startTime, endTime };
};

// 従事可能日（配列）⇔ 選択状態（{ 'yyyy-MM-dd': ['HH:mm-HH:mm', ...] }）
const toSelection = (kanoubiDates) => {
    const selection = {};
    (kanoubiDates || []).forEach((k) => {
        const keys = (k.timeSlots || []).map(slotKey);
        if (keys.length > 0) {
            selection[k.kanoubiDate] = [...new Set([...(selection[k.kanoubiDate] || []), ...keys])];
        }
    });
    return selection;
};
const toKanoubiDates = (selection) =>
    Object.keys(selection)
        .filter((date) => selection[date].length > 0)
        .sort()
        .map((date) => ({ kanoubiDate: date, timeSlots: [...selection[date]].sort().map(keyToSlot) }));

export default class JujJyujijigyouJisshibiShitei extends LightningElement {
    // 呼出し元（JUJ080）からの引継ぎ
    @api jigyoKey; // { jujiJigyoNo, jujiBasyoNo, jisiNendo }
    @api jujishaNo;
    @api kanoubiDates; // 保持中の従事可能日（JUJ080 の値）

    headerData = {};
    selection = {}; // 保持中の従事可能日
    initialSelection = {}; // クリア用の初期値
    ownAssigned = {}; // 本人割当済の時間帯
    days = {}; // 表示期間の実施日（キー：'yyyy-MM-dd'）
    expanded = {}; // 時間帯行を展開している日付
    selectedMonth; // 表示年月 'yyyy-MM'
    minMonth;
    maxMonth;
    textStyleClass = CELL_CLIP;
    headerMessages = [];
    isLoading = false;
    noJisshibi = false;

    // 項目ラベル取得用のオブジェクト情報
    objectApiNames = [JIGYO_OBJECT, BASYO_OBJECT, SODANIN_OBJECT, OFFICE_OBJECT];
    @wire(getObjectInfos, { objectApiNames: '$objectApiNames' })
    objectInfos;

    // ========== No.21 画面初期化 ==========
    async connectedCallback() {
        const key = this.jigyoKey || {};
        this.isLoading = true;
        try {
            // 従事事業・従事者・本人割当済の時間帯・実施日の範囲（最も早い実施日・最も遅い実施日）を取得する
            const result = await init({ ...key, jujishaNo: this.jujishaNo });
            // ヘッダー部の表示
            this.headerData = {
                jujiJigyoNo: key.jujiJigyoNo,
                jujiJigyoMei: result.jigyo.jigyoName,
                shibuCode: result.jigyo.shibuCode,
                shibuMei: result.jigyo.shibuName,
                jujiBashoNo: key.jujiBasyoNo,
                jujiBashoMei: result.jigyo.basyoName,
                jisshiNendo: key.jisiNendo,
                jujishaNo: this.jujishaNo,
                shiMei: result.jujishaName
            };
            // 本人割当済の時間帯のうち、受け取った従事可能日に含まれないものを追加して選択状態とする
            this.ownAssigned = toSelection(result.ownAssigned);
            const selection = toSelection(this.kanoubiDates);
            Object.keys(this.ownAssigned).forEach((date) => {
                selection[date] = [...new Set([...(selection[date] || []), ...this.ownAssigned[date]])];
            });
            this.selection = selection;
            this.initialSelection = JSON.parse(JSON.stringify(selection));

            // 実施日が1件も登録されていない場合：メッセージを表示し、閉じるボタン以外の項目・ボタンをすべて非活性とする
            if (!result.minJisshibi) {
                this.noJisshibi = true;
                this.headerMessages = [MSG.NO_JISSHIBI];
                return;
            }
            // 3.表示ラベル No.54 表示年月の移動可能な範囲：最も早い実施日の年月〜最も遅い実施日の年月
            this.minMonth = result.minJisshibi.slice(0, 7);
            this.maxMonth = result.maxJisshibi.slice(0, 7);
            // 表示年月の初期値：最も早い実施日がシステム日付より後の場合は最も早い実施日の年月、それ以外はシステム日付の年月
            // （範囲外の場合は範囲の開始または終了）
            const today = todayText();
            this.selectedMonth = this.toMonthInRange((result.minJisshibi > today ? result.minJisshibi : today).slice(0, 7));
            // No.34 一覧表示
            await this.loadDays();
        } catch (error) {
            // 従事事業・従事者を取得できなかった場合：画面を閉じ、JUJ080 の画面頭部にエラーメッセージを表示する
            this.dispatchEvent(new CustomEvent('close', { detail: { errorMessage: this.errorText(error) } }));
        } finally {
            this.isLoading = false;
        }
    }

    // ========== No.22 前月ボタン押下・No.23 次月ボタン押下・No.24 表示年月の選択 ==========
    handlePrevMonth() {
        this.changeMonth(addMonths(this.selectedMonth, -1));
    }

    handleNextMonth() {
        this.changeMonth(addMonths(this.selectedMonth, 1));
    }

    handleMonthChange(event) {
        this.changeMonth(event.detail.value);
    }

    // 表示年月を変更し（移動可能な範囲内に収める）、No.34 一覧表示を呼び出す（保持中の従事可能日は変更しない）
    changeMonth(ym) {
        const month = this.toMonthInRange(ym);
        if (month === this.selectedMonth) {
            return;
        }
        this.selectedMonth = month;
        this.loadDays();
    }

    // 移動可能な範囲（minMonth〜maxMonth）に収める
    toMonthInRange(ym) {
        if (ym < this.minMonth) {
            return this.minMonth;
        }
        return ym > this.maxMonth ? this.maxMonth : ym;
    }

    // ========== No.34 一覧表示呼び出し ==========
    // 表示期間（表示年月の1日〜末日）の実施日・割当人数を取得する（5.データ更新 (6)）
    async loadDays() {
        this.isLoading = true;
        try {
            const result = await getDays({ ...this.jigyoKey, fromDate: this.periodFrom, toDate: this.periodTo });
            const days = {};
            result.forEach((day) => {
                days[day.jisshibi] = day;
            });
            this.days = days;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== No.25 選択チェックボックス（日付行） ==========
    // ON でその日の選択可能な時間帯をすべて追加、OFF ですべて削除（本人割当済を除く）
    handleRowCheck(event) {
        const date = event.target.dataset.id;
        const day = this.days[date];
        if (!day) {
            return;
        }
        const keys = event.target.checked ? day.timeSlots.map(slotKey) : [];
        this.setDaySelection(date, keys);
    }

    // ========== No.26 選択チェックボックス（時間帯行） ==========
    // ON で追加、OFF で削除
    handleSubRowCheck(event) {
        const { date, key } = event.target.dataset;
        const current = new Set(this.selection[date] || []);
        if (event.target.checked) {
            current.add(key);
        } else {
            current.delete(key);
        }
        this.setDaySelection(date, [...current]);
    }

    // ========== No.27 全選択チェックボックス（一覧ヘッダー） ==========
    // ON で表示期間内の選択可能な時間帯をすべて追加、OFF ですべて削除（本人割当済を除く）
    // ※ 表示月チェックオフボタンは本チェックボックスと重複するため廃止（2026/10/16）
    handleMasterCheck(event) {
        const checked = event.target.checked;
        const selection = { ...this.selection };
        Object.values(this.days).forEach((day) => {
            selection[day.jisshibi] = this.withOwn(day.jisshibi, checked ? day.timeSlots.map(slotKey) : []);
        });
        this.selection = selection;
    }

    // ========== No.31 全チェックオフボタン押下 ==========
    // 保持中の従事可能日をすべて削除する（表示期間外の月を含む。本人割当済を除く）
    handleAllCheckOff() {
        this.selection = JSON.parse(JSON.stringify(this.ownAssigned));
    }

    // ========== No.32 クリアボタン押下 ==========
    // 選択状態を画面を開いた時の状態（JUJ080 から受け取った従事可能日＋本人割当済の時間帯）に戻す
    handleClear() {
        this.selection = JSON.parse(JSON.stringify(this.initialSelection));
        this.headerMessages = [];
    }

    // 指定日の選択を置き換える（本人割当済の時間帯は常に残す）
    setDaySelection(date, keys) {
        this.selection = { ...this.selection, [date]: this.withOwn(date, keys) };
    }

    withOwn(date, keys) {
        return [...new Set([...keys, ...(this.ownAssigned[date] || [])])];
    }

    // ========== No.28 展開ボタン（日付行）：時間帯行の表示／非表示（初期表示は非表示） ==========
    handleToggleExpand(event) {
        const date = event.currentTarget.dataset.id;
        this.expanded = { ...this.expanded, [date]: !this.expanded[date] };
    }

    // ========== No.29 列ヘッダーメニュー ==========
    handleWrapText() {
        this.textStyleClass = CELL_WRAP;
    }

    handleClipText() {
        this.textStyleClass = CELL_CLIP;
    }

    // 列幅の変更（未実装）
    handleMouseDown() {}

    // ========== No.30 保存ボタン押下 ==========
    async handleSave() {
        this.headerMessages = [];
        // 4.入力チェック No.23 一括割当実行中の場合はエラー
        try {
            await checkSave({ ...this.jigyoKey });
        } catch (error) {
            this.showError(error);
            return;
        }
        // 確認ダイアログ
        if (!(await LightningConfirm.open({ message: MSG.CONFIRM_SAVE, label: '保存確認' }))) {
            return;
        }
        // 保持中の従事可能日（日付と時間帯）を JUJ080 に返し、画面を閉じる（時間帯が1件もない日付は返さない。DB は更新しない）
        this.dispatchEvent(new CustomEvent('save', { detail: { kanoubiDates: toKanoubiDates(this.selection) } }));
    }

    // ========== No.33 閉じるボタン押下：JUJ080 に返さずに画面を閉じる ==========
    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { detail: {} }));
    }

    // ========== 共通 ==========
    showError(error) {
        this.headerMessages = [this.errorText(error)];
    }

    errorText(error) {
        return error?.body?.message || MSG.UNEXPECTED;
    }

    // 項目ラベル取得：指定オブジェクトの項目情報（未取得時は空オブジェクト）
    getFieldInfos(objectApiName) {
        const results = this.objectInfos?.data?.results || [];
        const info = results.find((r) => r.result && r.result.apiName === objectApiName);
        return info ? info.result.fields : {};
    }

    // ========== Getter ==========
    // 表示期間：表示年月の1日〜末日（3.表示ラベル No.54）
    get periodFrom() {
        return `${this.selectedMonth}-01`;
    }

    get periodTo() {
        const end = firstOfMonth(addMonths(this.selectedMonth, 1));
        end.setUTCDate(0); // 表示年月の末日
        return toDateText(end);
    }

    // 表示年月の選択肢（移動可能な範囲内の各年月）
    get monthOptions() {
        const options = [];
        if (!this.minMonth) {
            return options;
        }
        for (let ym = this.minMonth; ym <= this.maxMonth; ym = addMonths(ym, 1)) {
            options.push({ label: `${ym.slice(0, 4)}年${ym.slice(5, 7)}月`, value: ym });
        }
        return options;
    }

    // No.34 一覧の行（表示期間内の全日付の日付行＋時間帯行）
    get calendarRows() {
        if (!this.selectedMonth || this.noJisshibi) {
            return [];
        }
        const rows = [];
        const end = this.periodTo;
        for (let d = parseDate(this.periodFrom); toDateText(d) <= end; d.setUTCDate(d.getUTCDate() + 1)) {
            rows.push(this.buildRow(toDateText(d), d.getUTCDay()));
        }
        return rows;
    }

    buildRow(date, weekday) {
        const day = this.days[date];
        const selected = new Set(this.selection[date] || []);
        const own = new Set(this.ownAssigned[date] || []);
        // 時間帯行（実施日の時間帯ごと）
        const subRows = (day ? day.timeSlots : []).map((slot, i) => {
            const key = slotKey(slot);
            return {
                id: `${date}_${key}`,
                key,
                displayIndex: i + 1,
                startTime: slot.startTime,
                endTime: slot.endTime,
                boshuNinzu: slot.count,
                wariateNinzu: slot.wariateNinzu,
                // 時間帯行は区分による色付けをせず、統一のスタイルとする（3.表示ラベル No.60）
                rowClass: CHILD_ROW,
                isSelected: selected.has(key),
                // 本人割当済の時間帯は選択状態のまま選択不可（3.表示ラベル No.58）
                isDisabled: own.has(key)
            };
        });
        const isExpanded = !!this.expanded[date];
        return {
            id: date,
            dayLabel: date.replace(/-/g, '/'),
            youbi: WEEKDAYS[weekday],
            // 日曜日・祝日は赤字、土曜日は青字（3.表示ラベル No.61。【要確認 QA-05⑥】祝日は未対応）
            youbiClass: weekday === 0 ? YOUBI_SUNDAY : weekday === 6 ? YOUBI_SATURDAY : '',
            boshuNinzu: day ? day.boshuNinzu : null,
            wariateNinzu: day ? day.wariateNinzu : null,
            startTime: day ? day.startTime : null,
            endTime: day ? day.endTime : null,
            biko: day ? day.biko : null,
            // 日付行の区分（3.表示ラベル No.60）：割当人数が1以上の時間帯あり → 割当、実施日あり → 募集、実施日なし → 色付けなし
            rowClass: !day ? '' : subRows.some((s) => s.wariateNinzu > 0) ? ROW_WARIATE : ROW_BOSHU,
            // 時間帯が1件以上選択されていれば選択状態（3.表示ラベル No.57）
            isSelected: subRows.some((s) => s.isSelected),
            // 実施日なし、またはすべての時間帯が本人割当済の場合は選択不可（3.表示ラベル No.57）
            isDisabled: !day || subRows.every((s) => s.isDisabled),
            hasSubRows: subRows.length > 0,
            isExpanded,
            expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            subRows
        };
    }

    // No.27 全選択チェックボックス：表示期間内の選択可能な時間帯がすべて選択されている場合 ON
    get isAllSelected() {
        const selectable = [];
        Object.values(this.days).forEach((day) => {
            day.timeSlots.forEach((slot) => selectable.push([day.jisshibi, slotKey(slot)]));
        });
        return selectable.length > 0 && selectable.every(([date, key]) => (this.selection[date] || []).includes(key));
    }

    // No.22・No.23 前月・次月：表示年月が移動可能な範囲の開始・終了の場合は非活性
    // 実施日がない場合は閉じるボタン以外を非活性とする
    get isPrevDisabled() {
        return this.isActionDisabled || this.selectedMonth <= this.minMonth;
    }

    get isNextDisabled() {
        return this.isActionDisabled || this.selectedMonth >= this.maxMonth;
    }

    get isActionDisabled() {
        return this.noJisshibi || this.isLoading;
    }

    get hasHeaderMessages() {
        return this.headerMessages.length > 0;
    }

    // ========== Getter（3.表示ラベル） ==========
    // 画面項目のラベル（メタデータから取得。取得できない場合は既定ラベル。取得元が「固定」の項目は固定値）
    get labels() {
        const labels = { ...FIXED_LABELS };
        Object.entries(LABEL_FIELDS).forEach(([key, [objectApiName, field, defaultLabel]]) => {
            const fieldInfo = this.getFieldInfos(objectApiName)[field];
            labels[key] = fieldInfo ? fieldInfo.label : defaultLabel;
        });
        return labels;
    }
}
