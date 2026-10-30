/**
 * JUJ081 従事可能日指定（JUJ080 の子コンポーネントとしてモーダル表示する）
 * ※ DB は更新しない。保存時に選択した従事可能日を JUJ080 へ返す。
 * ※ 従事可能日は時間帯単位で選択する：[{ kanoubiDate: 'yyyy-MM-dd', timeSlots: [{ startTime, endTime }] }]
 *   時間帯は開始時間＋終了時間で照合する。
 *
 * 呼出し元（JUJ080）：
 *   <c-juj_-jyujijigyou-jisshibi-shitei jigyo-key={jigyoKey} jujisha-no={jujishaNo} kanoubi-dates={kanoubiDates}
 *             onsave={...} onclose={...}></c-juj_-jyujijigyou-jisshibi-shitei>
 * イベント：
 *   save  … 保存時。detail = { kanoubiDates }
 *   close … 閉じる時。初期表示エラーで閉じる場合は detail = { errorMessage }
 */
import { LightningElement, api, wire } from 'lwc';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';

import init from '@salesforce/apex/Juj_JyujijigyouJisshibiShiteiController.init';
import getDays from '@salesforce/apex/Juj_JyujijigyouJisshibiShiteiController.getDays';
import checkSave from '@salesforce/apex/Juj_JyujijigyouJisshibiShiteiController.checkSave';

// メッセージ【要確認 QA-20】
const MSG = {
    NO_JISSHIBI: '実施日が登録されていません。',
    CONFIRM_SAVE:
        '保存します。よろしいですか？\n※この時点では応募は確定されません。応募を確定するには元画面で登録ボタンを押下してください。', // WLP009-0004
    UNEXPECTED: '予期しないエラーが発生しました。'
};

// 行の区分（CSS クラス）
const ROW_WARIATE = 'row-status-waritate'; // 割当
const ROW_BOSHU = 'row-status-oubo'; // 募集
const CHILD_ROW = 'child-row'; // 時間帯行
const YOUBI_SATURDAY = 'youbi-saturday';
const YOUBI_SUNDAY = 'youbi-sunday'; // 日曜・祝日
const CELL_CLIP = 'cell-clip';
const CELL_WRAP = 'cell-wrap';

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

// 項目ラベルの取得元オブジェクト
const JIGYO_OBJECT = 'Juji_Jigyo__c'; // 従事事業
const BASYO_OBJECT = 'Juji_Basyo_Master__c'; // 従事場所マスタ
const SODANIN_OBJECT = 'Soudanin_Master__c'; // 相談員マスタ（氏名。JUJ080 と同じ）
const OFFICE_OBJECT = 'Account'; // 事務所・法人

// 画面項目 → [オブジェクト, 項目名, 既定ラベル]（項目ラベルを取得できない場合は既定ラベル。一覧の列名は固定）
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

// 固定ラベルの項目
const FIXED_LABELS = {
    jujishaNo: '登録番号/相談員番号'
};

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

// 時間帯の照合キー（開始時間＋終了時間）
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
    // JUJ080 からの引継ぎ
    @api jigyoKey; // { jujiJigyoNo, jujiBasyoNo, jisiNendo }
    @api jujishaNo;
    @api kanoubiDates;

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

    pageOverflow = ''; // 表示前のページのスクロール設定（閉じたときに戻す）

    // 確認ダイアログ
    isConfirmOpen = false;
    confirm = { message: '', label: '' };
    confirmResolve = null;
    noJisshibi = false;

    // 項目ラベルの取得
    objectApiNames = [JIGYO_OBJECT, BASYO_OBJECT, SODANIN_OBJECT, OFFICE_OBJECT];
    @wire(getObjectInfos, { objectApiNames: '$objectApiNames' })
    objectInfos;

    // ========== 画面初期化 ==========
    async connectedCallback() {
        this.lockPageScroll();
        const key = this.jigyoKey || {};
        this.isLoading = true;
        try {
            const result = await init({ ...key, jujishaNo: this.jujishaNo });
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

            // 実施日がない場合は閉じるボタン以外を非活性とする（getter で制御）
            if (!result.minJisshibi) {
                this.noJisshibi = true;
                this.headerMessages = [MSG.NO_JISSHIBI];
                return;
            }
            // 表示年月の範囲：最も早い実施日の年月〜最も遅い実施日の年月
            this.minMonth = result.minJisshibi.slice(0, 7);
            this.maxMonth = result.maxJisshibi.slice(0, 7);
            // 初期値：最も早い実施日がシステム日付より後なら最も早い実施日の年月、それ以外はシステム日付の年月（範囲内に収める）
            const today = todayText();
            this.selectedMonth = this.toMonthInRange((result.minJisshibi > today ? result.minJisshibi : today).slice(0, 7));
            await this.loadDays();
        } catch (error) {
            // 従事事業・従事者を取得できなかった場合は画面を閉じ、JUJ080 にエラーを表示する
            this.dispatchEvent(new CustomEvent('close', { detail: { errorMessage: this.errorText(error) } }));
        } finally {
            this.isLoading = false;
        }
    }

    // ========== 前月・次月・表示年月の選択 ==========
    handlePrevMonth() {
        this.changeMonth(addMonths(this.selectedMonth, -1));
    }

    handleNextMonth() {
        this.changeMonth(addMonths(this.selectedMonth, 1));
    }

    handleMonthChange(event) {
        this.changeMonth(event.detail.value);
    }

    // 表示年月を変更して一覧を再表示する（選択中の従事可能日は保持する）
    changeMonth(ym) {
        const month = this.toMonthInRange(ym);
        if (month === this.selectedMonth) {
            return;
        }
        this.selectedMonth = month;
        this.loadDays();
    }

    // minMonth〜maxMonth に収める
    toMonthInRange(ym) {
        if (ym < this.minMonth) {
            return this.minMonth;
        }
        return ym > this.maxMonth ? this.maxMonth : ym;
    }

    // ========== 一覧表示 ==========
    // 表示期間（表示年月の1日〜末日）の実施日・割当人数を取得する
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

    // ========== 選択チェックボックス（日付行） ==========
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

    // ========== 選択チェックボックス（時間帯行） ==========
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

    // ========== 全選択チェックボックス（一覧ヘッダー） ==========
    // ON で表示期間内の選択可能な時間帯をすべて追加、OFF ですべて削除（本人割当済を除く）
    handleMasterCheck(event) {
        const checked = event.target.checked;
        const selection = { ...this.selection };
        Object.values(this.days).forEach((day) => {
            selection[day.jisshibi] = this.withOwn(day.jisshibi, checked ? day.timeSlots.map(slotKey) : []);
        });
        this.selection = selection;
    }

    // ========== 全チェックオフ ==========
    // 表示期間外の月を含めてすべて削除する（本人割当済を除く）
    handleAllCheckOff() {
        this.selection = JSON.parse(JSON.stringify(this.ownAssigned));
    }

    // ========== クリア ==========
    // 画面を開いた時の選択状態（JUJ080 から受け取った従事可能日＋本人割当済）に戻す
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

    // ========== 展開ボタン（日付行）：時間帯行の表示／非表示 ==========
    handleToggleExpand(event) {
        const date = event.currentTarget.dataset.id;
        this.expanded = { ...this.expanded, [date]: !this.expanded[date] };
    }

    // ========== 列ヘッダーメニュー ==========
    handleWrapText() {
        this.textStyleClass = CELL_WRAP;
    }

    handleClipText() {
        this.textStyleClass = CELL_CLIP;
    }

    // 列幅の変更（未実装）
    handleMouseDown() {}

    // ========== 保存 ==========
    async handleSave() {
        this.headerMessages = [];
        try {
            await checkSave({ ...this.jigyoKey });
        } catch (error) {
            this.showError(error);
            return;
        }
        if (!(await this.confirmDialog(MSG.CONFIRM_SAVE, '保存確認'))) {
            return;
        }
        // 時間帯が1件もない日付は返さない
        this.dispatchEvent(new CustomEvent('save', { detail: { kanoubiDates: toKanoubiDates(this.selection) } }));
    }

    disconnectedCallback() {
        this.unlockPageScroll();
    }

    // 表示中は背面の画面（JUJ080）がマウスホイールでスクロールしないよう、ページのスクロールを止める
    // （閉じたとき＝本コンポーネントが削除されたときに元に戻す）
    // ※ ページの要素を操作できない環境（Lightning Locker 等）では何もしない（画面の処理は続ける）
    lockPageScroll() {
        try {
            this.pageOverflow = document.body.style.overflow;
            document.body.style.overflow = 'hidden';
        } catch (e) {
            // スクロールを止められない場合はそのまま表示する
        }
    }

    unlockPageScroll() {
        try {
            document.body.style.overflow = this.pageOverflow || '';
        } catch (e) {
            // 同上
        }
    }

    // ========== 閉じる（JUJ080 に返さない） ==========
    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { detail: {} }));
    }

    // ========== 確認ダイアログ（はい／いいえ）。「はい」の場合 true を返す ==========
    confirmDialog(message, label) {
        this.confirm = { message, label };
        this.isConfirmOpen = true;
        return new Promise((resolve) => {
            this.confirmResolve = resolve;
        });
    }

    handleConfirmYes() {
        this.closeConfirm(true);
    }

    handleConfirmNo() {
        this.closeConfirm(false);
    }

    closeConfirm(result) {
        this.isConfirmOpen = false;
        this.confirmResolve(result);
        this.confirmResolve = null;
    }

    // ========== 共通 ==========
    showError(error) {
        this.headerMessages = [this.errorText(error)];
    }

    errorText(error) {
        return error?.body?.message || MSG.UNEXPECTED;
    }

    getFieldInfos(objectApiName) {
        const results = this.objectInfos?.data?.results || [];
        const info = results.find((r) => r.result && r.result.apiName === objectApiName);
        return info ? info.result.fields : {};
    }

    // ========== Getter ==========
    // 表示期間：表示年月の1日〜末日
    get periodFrom() {
        return `${this.selectedMonth}-01`;
    }

    get periodTo() {
        const end = firstOfMonth(addMonths(this.selectedMonth, 1));
        end.setUTCDate(0); // 末日
        return toDateText(end);
    }

    // 表示年月の選択肢
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

    // 一覧の行（表示期間内の全日付の日付行＋時間帯行）
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
                // 時間帯行は区分による色付けをしない
                rowClass: CHILD_ROW,
                isSelected: selected.has(key),
                // 本人割当済の時間帯は選択状態のまま選択不可
                isDisabled: own.has(key)
            };
        });
        const isExpanded = !!this.expanded[date];
        return {
            id: date,
            dayLabel: `${Number(date.slice(5, 7))}月${Number(date.slice(8, 10))}日`, // M月d日（0埋めなし。年は表示年月で示す）
            youbi: WEEKDAYS[weekday],
            // 日曜日は赤字、土曜日は青字【要確認 QA-05⑥】祝日
            youbiClass: weekday === 0 ? YOUBI_SUNDAY : weekday === 6 ? YOUBI_SATURDAY : '',
            boshuNinzu: day ? day.boshuNinzu : null,
            wariateNinzu: day ? day.wariateNinzu : null,
            startTime: day ? day.startTime : null,
            endTime: day ? day.endTime : null,
            biko: day ? day.biko : null,
            // 日付行の区分：割当人数が1以上の時間帯あり → 割当、実施日あり → 募集、実施日なし → 色付けなし
            rowClass: !day ? '' : subRows.some((s) => s.wariateNinzu > 0) ? ROW_WARIATE : ROW_BOSHU,
            isSelected: subRows.some((s) => s.isSelected),
            // 実施日なし、またはすべての時間帯が本人割当済の場合は選択不可
            isDisabled: !day || subRows.every((s) => s.isDisabled),
            hasSubRows: subRows.length > 0,
            isExpanded,
            expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            subRows
        };
    }

    // 全選択：表示期間内の選択可能な時間帯がすべて選択されている場合 ON
    get isAllSelected() {
        const selectable = [];
        Object.values(this.days).forEach((day) => {
            day.timeSlots.forEach((slot) => selectable.push([day.jisshibi, slotKey(slot)]));
        });
        return selectable.length > 0 && selectable.every(([date, key]) => (this.selection[date] || []).includes(key));
    }

    // 前月・次月：範囲の開始・終了の場合は非活性
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

    // 画面項目のラベル（項目ラベル。取得できない場合は既定ラベル）
    get labels() {
        const labels = { ...FIXED_LABELS };
        Object.entries(LABEL_FIELDS).forEach(([key, [objectApiName, field, defaultLabel]]) => {
            const fieldInfo = this.getFieldInfos(objectApiName)[field];
            labels[key] = fieldInfo ? fieldInfo.label : defaultLabel;
        });
        return labels;
    }
}
