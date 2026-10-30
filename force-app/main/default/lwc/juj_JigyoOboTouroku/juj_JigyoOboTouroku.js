/**
 * JUJ080 従事事業応募登録
 * 従事事業メニュー（juj_JigyoMenu）の子画面として表示する。
 *   <c-juj_-jigyo-obo-touroku record-data={selectedRecordData} onback={...} onshowparentmenu={...}>
 *   record-data：従事事業基本情報表示から遷移した場合は従事事業（jujiJigyoNo・jujiBashoNo・jisshiNendo）、メニューからは null
 * イベント：
 *   back           … 戻るボタン（メニューが直前の画面またはメニューに戻す）
 *   showparentmenu … メニューボタン
 * ※ jujisha・jigyo は html から直接参照する（jujisha.name 等）ため null を代入しない。
 *   未取得時は空オブジェクト {} とし、判定には hasJujisha / hasJigyo を使用する。
 */
import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';

import getJigyo from '@salesforce/apex/Juj_JigyoOboTourokuController.getJigyo';
import getJujisha from '@salesforce/apex/Juj_JigyoOboTourokuController.getJujisha';
import loadApplication from '@salesforce/apex/Juj_JigyoOboTourokuController.loadApplication';
import checkJigyo from '@salesforce/apex/Juj_JigyoOboTourokuController.checkJigyo';
import saveApplication from '@salesforce/apex/Juj_JigyoOboTourokuController.saveApplication';
import deleteApplication from '@salesforce/apex/Juj_JigyoOboTourokuController.deleteApplication';
import deleteAllApplications from '@salesforce/apex/Juj_JigyoOboTourokuController.deleteAllApplications';

// 共通の検索子画面（JUJ110・120・140）の重なり順
const SUB_SCREEN_LEVEL = 1;

// 検索子画面・従事事業基本情報表示から受け取る値は数値の場合もあるため文字列にする
const toText = (value) => (value == null ? '' : String(value));

// 遷移元
const FROM_JIGYO_INFO = 'JIGYO_INFO'; // 従事事業基本情報
const FROM_MENU = 'MENU'; // 従事事業メニュー

// メッセージ【要確認 QA-20】カスタム表示ラベルへの置き換え
const MSG = {
    REQUIRED: (label) => `${label}は必須入力項目です。`,
    NENDO_FORMAT: '実施年度は4桁の半角数字（西暦）で入力してください。',
    KIBOU_NISSU_FORMAT: '希望従事日数は3桁以内の1以上の半角数字で入力してください。',
    TEL_FORMAT: (label) => `${label}は半角数字またはハイフンで入力してください。`,
    JIGYO_KEY_REQUIRED: '従事事業No、従事場所No、実施年度を入力してください。', // 従事事業基本情報からの遷移でキーが欠けている場合（防御用）
    JIGYO_NOT_FOUND: '従事事業が存在しません。',
    JUJISHA_NOT_FOUND: '従事者が存在しません。',
    WEEKDAY_REQUIRED: '従事可能曜日を選択してください。',
    KANOUBI_REQUIRED: '従事可能日を指定してください。',
    SKILL_REQUIRED: 'スキルを選択してください。',
    CONFIRM_OVERWRITE: '入力中の応募情報は破棄されます。よろしいですか？',
    CONFIRM_SAVE: '入力された内容で応募情報を登録してよろしいですか？', // WLP007-0001
    CONFIRM_DELETE: '削除します。よろしいですか？',
    CONFIRM_DELETE_ALL_1: '以下の事業に関する応募情報を全て削除します。この操作は取り消すことは出来ません',
    CONFIRM_DELETE_ALL_2: '応募情報を全て削除します。本当によろしいですか？',
    CONFIRM_DISCARD: '未登録の変更があります。破棄してよろしいですか？',
    SAVED: '登録しました。',
    DELETED: '削除しました。'
};

// 確認ダイアログのタイトル（押下したボタン名＋「確認」）
const TITLE = {
    SHOW_APPLICATION: '応募情報表示確認',
    SAVE: '登録確認',
    DELETE: '削除確認',
    DELETE_ALL: '全削除確認',
    CLEAR: 'クリア確認',
    BACK: '戻る確認',
    MENU: 'メニュー確認'
};

// 実施年度：半角数字4桁（西暦）
const NENDO_PATTERN = /^[0-9]{4}$/;
// 連絡先（固定電話・携帯電話・FAX）：半角数字とハイフン（桁数は html の max-length＝項目の桁数 14）
// ※ pattern 属性は v フラグの正規表現として評価されるため、ハイフンはエスケープする（未エスケープだと正規表現が無効になりチェックされない）
const TEL_PATTERN = '[0-9\\-]*';

// 従事経験の値
const KEIKEN_ARI = '有';
const KEIKEN_NASHI = '無';

// スキル評価の選択肢
const SKILL_OPTIONS = [
    { label: '5(得意)', value: '5' },
    { label: '4', value: '4' },
    { label: '3', value: '3' },
    { label: '2', value: '2' },
    { label: '1(不得意)', value: '1' }
];

// 項目ラベルの取得元オブジェクト
const OBO_OBJECT = 'Juji_Jigyo_Oubo__c'; // 従事事業応募
const JIGYO_OBJECT = 'Juji_Jigyo__c'; // 従事事業
const BASYO_OBJECT = 'Juji_Basyo_Master__c'; // 従事場所マスタ
const SODANIN_OBJECT = 'Soudanin_Master__c'; // 相談員マスタ
const OFFICE_OBJECT = 'Account'; // 事務所・法人

// 画面項目 → [オブジェクト, 項目名, 既定ラベル]（項目ラベルを取得できない場合は既定ラベルを表示する）
const LABEL_FIELDS = {
    jujiJigyoNo: [JIGYO_OBJECT, 'Juji_Juji_Jigyo_No__c', '従事事業No.'],
    jigyoName: [JIGYO_OBJECT, 'Juji_Juji_Jigyo_Name__c', '従事事業名'],
    jisiNendo: [JIGYO_OBJECT, 'Juji_Jisi_Nendo__c', '実施年度'],
    jujiBasyoNo: [BASYO_OBJECT, 'JujM_Juji_Basyo_No__c', '従事場所No.'],
    basyoName: [BASYO_OBJECT, 'JujM_Juji_Basyo_Name__c', '従事場所名'],
    shibuCode: [OFFICE_OBJECT, 'Jims_Sibu_Code__c', '支部コード'],
    shibuName: [OFFICE_OBJECT, 'Jims_Sibu_Name__c', '支部名'],
    uketukeNo: [OBO_OBJECT, 'Oubo_Uketuke_No__c', '受付番号'],
    kibouNissu: [OBO_OBJECT, 'Oubo_Kibo_Juji_Nisu__c', '希望従事日数'],
    keiken: [OBO_OBJECT, 'Oubo_Juji_Keiken__c', '従事経験'],
    telFixed: [OBO_OBJECT, 'Oubo_Renrakusaki_Kotei_No__c', '連絡先(固定電話)'],
    telMobile: [OBO_OBJECT, 'Oubo_Renrakusaki_Tel_No__c', '連絡先(携帯電話)'],
    fax: [OBO_OBJECT, 'Oubo_Renrakusaki_Fax_No__c', '連絡先(FAX)'],
    mail: [OBO_OBJECT, 'Oubo_Renrakusaki_Mail__c', '連絡先(Mail)'],
    biko: [OBO_OBJECT, 'Oubo_Biko__c', '備考'],
    skillNote: [OBO_OBJECT, 'Oubo_Skill_Toki_Jiko__c', 'スキル特記事項'],
    chosho: [OBO_OBJECT, 'Oubo_Tyosyo_Ronbun__c', '主な著書、論文'],
    sodanKamoku: [OBO_OBJECT, 'Oubo_Sodan_Kamoku__c', '相談科目'],
    // 従事者情報部は会員・相談員とも相談員マスタの項目ラベルを使用する
    jujishaName: [SODANIN_OBJECT, 'SouM_Sodanin_Name__c', '氏名'],
    jujishaFurigana: [SODANIN_OBJECT, 'SouM_Sodanin_Name_Furigana__c', 'フリガナ'],
    jujishaAddress: [SODANIN_OBJECT, 'SouM_Jimusyo_Jusyo__c', '事務所住所'],
    jujishaTel: [SODANIN_OBJECT, 'SouM_Jimusyo_Tel_No__c', '事務所電話番号'],
    jujishaFax: [SODANIN_OBJECT, 'SouM_Jimusyo_Fax_No__c', '事務所FAX番号']
};

// 固定ラベルの項目
const FIXED_LABELS = {
    jujishaNo: '登録番号/相談員番号'
};

// スキル（8科目）：[項目名, 表示ラベル]。サーバとは項目名をキーに受け渡す
// ※ 画面のラベルは項目ラベルと異なるため固定値とする
const SKILL_FIELDS = [
    ['Oubo_Skill_Syotoku_Zei__c', '(所得税)'],
    ['Oubo_Skill_Kaisyaho__c', '(会社法)'],
    ['Oubo_Skill_Hojin_Zei__c', '(法人税)'],
    ['Oubo_Skill_Zaimu_Kaikei__c', '(財務会計)'],
    ['Oubo_Skill_Sisan_Zei__c', '(資産税)'],
    ['Oubo_Skill_Joto_Sanrin__c', '(譲渡山林)'],
    ['Oubo_Skill_Syohi_Zei__c', '(消費税)'],
    ['Oubo_Skill_Zoyo_Zei__c', '(贈与税)']
];

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

const emptyJigyoKey = () => ({ jujiJigyoNo: '', jujiBasyoNo: '', jisiNendo: '' });

// 必須チェックのグループ（html の data-required の値）
const REQUIRED_JIGYO_KEY = 'jigyoKey'; // 従事事業No・従事場所No・実施年度
const REQUIRED_JUJISHA = 'jujisha'; // 登録番号/相談員番号

// 応募情報部の初期値
const emptyForm = () => ({
    telFixed: '',
    telMobile: '',
    fax: '',
    mail: '',
    biko: '',
    allDays: false, // 全日程従事可能
    weekdays: [], // 従事可能曜日（'月'、'火' 等）
    kibouNissu: null,
    keiken: KEIKEN_ARI,
    skills: [], // [{ field: 項目名, value: 選択値 }]
    skillNote: '',
    chosho: '',
    sodanKamoku: ''
});

export default class JujJigyoOboTouroku extends LightningElement {
    @api recordData; // 従事事業基本情報表示からの引継ぎ（メニューからは null）

    fromScreen = FROM_MENU;

    // 従事事業キー部
    jigyoKey = emptyJigyoKey();
    prevJigyoKey = emptyJigyoKey();
    basyoName = '';
    jigyo = {}; // {}＝未取得
    lastUketukeNo = null;

    // 従事者情報部
    jujishaNo = '';
    prevJujishaNo = '';
    jujisha = {}; // {}＝未取得
    uketukeNo = null;

    // 応募情報部
    applicationId = null; // null＝追加モード
    systemModstamp = null; // 排他チェック用
    meisaiVersion = null; // 応募明細の排他チェック用
    form = emptyForm();
    kanoubiDates = []; // [{ kanoubiDate: 'yyyy-MM-dd', timeSlots: [{ startTime, endTime }] }]

    // 子画面の表示有無
    isApplicationSearchOpen = false; // JUJ082
    isKanoubiOpen = false; // JUJ081
    isJigyoSearchOpen = false; // JUJ110
    isBasyoSearchOpen = false; // JUJ120
    isJujishaSearchOpen = false; // JUJ140
    subScreenLevel = SUB_SCREEN_LEVEL;
    isDirty = false; // 未登録の変更有無
    isLoading = false;
    headerMessages = []; // 画面頭部のエラーメッセージ

    // 背面の画面のスクロール制御（template では使用しない）
    isPageScrollLocked = false;
    pageOverflow = '';

    // 確認ダイアログ
    isConfirmOpen = false;
    confirm = { message: '', label: '' };
    confirmResolve = null;

    // 項目ラベルの取得
    objectApiNames = [OBO_OBJECT, JIGYO_OBJECT, BASYO_OBJECT, SODANIN_OBJECT, OFFICE_OBJECT];
    @wire(getObjectInfos, { objectApiNames: '$objectApiNames' })
    objectInfos;

    // ========== 画面初期化 ==========
    // メニューは画面を切り替えるたびに本コンポーネントを作り直すため、表示のたびに初期化される
    connectedCallback() {
        this.initialize(this.recordData);
    }

    renderedCallback() {
        this.syncPageScroll();
    }

    disconnectedCallback() {
        if (this.isPageScrollLocked) {
            this.setPageOverflow(this.pageOverflow || '');
        }
    }

    // 共通の検索子画面・確認ダイアログの表示中は、背面の画面がマウスホイールでスクロールしないよう、ページのスクロールを止める
    // ※ JUJ081・JUJ082 は各コンポーネントで制御する
    syncPageScroll() {
        const isSubScreenOpen = this.isConfirmOpen || this.isJigyoSearchOpen || this.isBasyoSearchOpen || this.isJujishaSearchOpen;
        if (isSubScreenOpen && !this.isPageScrollLocked) {
            try {
                this.pageOverflow = document.body.style.overflow;
            } catch (e) {
                this.pageOverflow = '';
            }
            this.setPageOverflow('hidden');
            this.isPageScrollLocked = true;
        } else if (!isSubScreenOpen && this.isPageScrollLocked) {
            this.setPageOverflow(this.pageOverflow || '');
            this.isPageScrollLocked = false;
        }
    }

    // ※ ページの要素を操作できない環境（Lightning Locker 等）では何もしない（画面の処理は続ける）
    setPageOverflow(value) {
        try {
            document.body.style.overflow = value;
        } catch (e) {
            // スクロールを止められない場合はそのまま表示する
        }
    }

    async initialize(recordData) {
        this.resetJujishaAndApplication();
        // 従事事業基本情報表示から遷移した場合は、引き継いだ従事事業キーで事業を取得する
        if (recordData) {
            this.fromScreen = FROM_JIGYO_INFO;
            this.jigyoKey = {
                jujiJigyoNo: toText(recordData.jujiJigyoNo),
                jujiBasyoNo: toText(recordData.jujiBashoNo),
                jisiNendo: toText(recordData.jisshiNendo)
            };
            await this.loadJigyo();
            this.prevJigyoKey = { ...this.jigyoKey };
        }
    }

    // ========== 従事事業キーのフォーカスアウト ==========
    handleJigyoKeyBlur(event) {
        const field = event.target.dataset.field;
        this.jigyoKey = { ...this.jigyoKey, [field]: event.target.value };
        this.onJigyoKeyChanged();
    }

    // ========== 従事事業検索（JUJ110） ==========
    // フォーカスアウトと同じ扱いのため、メッセージは消去しない
    handleJigyoSearchClick() {
        this.isJigyoSearchOpen = true;
    }

    // 選択された事業のキーを設定し、フォーカスアウトと同じ処理を行う
    handleJigyoSearchSelect(event) {
        this.isJigyoSearchOpen = false;
        const rec = event.detail.selectedRecord;
        this.jigyoKey = {
            jujiJigyoNo: toText(rec.jigyoNo),
            jujiBasyoNo: toText(rec.bashoNo),
            jisiNendo: toText(rec.nendo)
        };
        this.onJigyoKeyChanged();
    }

    handleJigyoSearchClose() {
        this.isJigyoSearchOpen = false;
    }

    // ========== 従事場所検索（JUJ120） ==========
    handleBasyoSearchClick() {
        this.isBasyoSearchOpen = true;
    }

    // 選択された従事場所No. を設定し、フォーカスアウトと同じ処理を行う
    handleBasyoSearchSelect(event) {
        this.isBasyoSearchOpen = false;
        const rec = event.detail.selectedRecord;
        this.jigyoKey = { ...this.jigyoKey, jujiBasyoNo: toText(rec.bashoNo) };
        this.onJigyoKeyChanged();
    }

    handleBasyoSearchClose() {
        this.isBasyoSearchOpen = false;
    }

    // 従事事業キーの変更
    async onJigyoKeyChanged() {
        // 入力された項目の未入力エラーのみ消去する（頭部メッセージは次のボタン押下まで保持する）
        this.clearRequiredErrors(REQUIRED_JIGYO_KEY, this.jigyoKey);
        await this.loadJigyo();
        // キーが変わった場合は応募情報部を初期化して追加モードとする（従事者は保持し、確認ダイアログは表示しない）
        if (!this.isSameJigyoKey(this.jigyoKey, this.prevJigyoKey)) {
            this.resetApplicationForm();
        }
        this.prevJigyoKey = { ...this.jigyoKey };
    }

    // ========== 従事場所名・従事事業の取得 ==========
    async loadJigyo() {
        const { jujiJigyoNo, jujiBasyoNo, jisiNendo } = this.jigyoKey;
        // 従事場所No. が変わっていない場合、従事場所名は再設定しない（表示のちらつき防止）
        const isBasyoChanged = jujiBasyoNo !== this.prevJigyoKey.jujiBasyoNo;
        if (isBasyoChanged) {
            this.basyoName = '';
        }
        // キーが変わった場合は、取得中に旧事業の設定で入力・登録できないよう先に空白とする
        // （変わっていない場合は表示のちらつき防止のため保持する）
        if (!this.isSameJigyoKey(this.jigyoKey, this.prevJigyoKey)) {
            this.jigyo = {};
            this.lastUketukeNo = null;
        }
        // 従事場所No. のみでは従事場所名、3項目すべてで従事事業を取得する
        if (!jujiBasyoNo && !(jujiJigyoNo && jisiNendo)) {
            return;
        }
        try {
            const result = await getJigyo({ ...this.jigyoKey });
            if (isBasyoChanged) {
                this.basyoName = result.basyoName || '';
            }
            // 取得できなかった場合は応募情報部が非活性になる（isApplicationDisabled）
            this.jigyo = result.jigyo || {};
            this.lastUketukeNo = result.jigyo ? result.jigyo.lastUketukeNo : null;
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 登録番号/相談員番号のフォーカスアウト ==========
    handleJujishaNoBlur(event) {
        this.jujishaNo = event.target.value;
        this.onJujishaNoChanged();
    }

    // ========== 従事対象者検索（JUJ140） ==========
    handleJujishaSearchClick() {
        this.isJujishaSearchOpen = true;
    }

    // 選択された従事者の番号を設定し、フォーカスアウトと同じ処理を行う
    handleJujishaSearchSelect(event) {
        this.isJujishaSearchOpen = false;
        const rec = event.detail.selectedRecord;
        this.jujishaNo = toText(rec.startNo); // 登録番号があれば登録番号、なければ相談員番号
        this.onJujishaNoChanged();
    }

    handleJujishaSearchClose() {
        this.isJujishaSearchOpen = false;
    }

    // 登録番号/相談員番号の変更
    async onJujishaNoChanged() {
        this.clearRequiredErrors(REQUIRED_JUJISHA, { jujishaNo: this.jujishaNo });
        if (this.jujishaNo === this.prevJujishaNo) {
            return;
        }
        this.prevJujishaNo = this.jujishaNo;
        await this.loadJujisha();
        // 受付番号・従事可能日のみ初期化して追加モードとする（応募情報部のその他の入力は保持する）
        this.kanoubiDates = [];
        this.uketukeNo = null;
        this.toAddMode();
    }

    // ========== 従事者の取得（取得できない場合はエラーとせず空白表示） ==========
    async loadJujisha() {
        this.jujisha = {};
        if (!this.jujishaNo) {
            return;
        }
        try {
            const result = await getJujisha({ jujishaNo: this.jujishaNo });
            this.jujisha = result || {};
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 応募情報表示 ==========
    async handleShowApplicationClick() {
        this.clearMessages();
        // エラーをまとめて表示するため、すべてのチェックを行ってから判定する（従事者の存在はサーバ側でチェック）
        const errors = [];
        const isValid = [this.validateJujishaNo(), this.validateJigyoKey(errors)].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        if (this.isDirty && !(await this.confirmDialog(MSG.CONFIRM_OVERWRITE, TITLE.SHOW_APPLICATION))) {
            return;
        }
        try {
            const result = await loadApplication({ ...this.jigyoKey, jujishaNo: this.jujishaNo });
            this.resetApplicationForm();
            this.jujisha = result.jujisha || {};
            this.prevJujishaNo = this.jujishaNo;
            // 応募がある場合は変更モード、ない場合は追加モード
            if (result.application) {
                this.applyApplication(result.application);
            }
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 応募情報検索（JUJ082） ==========
    handleApplicationSearchClick() {
        this.clearMessages();
        this.isApplicationSearchOpen = true;
    }

    handleApplicationSearchClose() {
        this.isApplicationSearchOpen = false;
    }

    // 応募が選択された場合
    async handleApplicationSearchSelect(event) {
        this.isApplicationSearchOpen = false;
        const { applicationId } = event.detail;
        try {
            const res = await loadApplication({ applicationId });
            // 従事事業メニューから遷移した場合は、選択された応募の従事事業キーに切り替える
            if (this.fromScreen === FROM_MENU) {
                this.jigyoKey = { ...res.jigyoKey };
                await this.loadJigyo();
                this.prevJigyoKey = { ...this.jigyoKey };
            }
            // 選択された応募を変更モードで表示する
            this.jujishaNo = res.jujishaNo;
            this.prevJujishaNo = res.jujishaNo;
            this.jujisha = res.jujisha || {};
            this.applyApplication(res.application);
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 従事可能日入力（JUJ081） ==========
    async handleKanoubiInputClick() {
        this.clearMessages();
        const errors = [];
        const isValid = [this.validateJigyoKey(errors), this.validateJujisha(errors)].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        // 実施日の有無・一括割当実行中（サーバ側でチェック）
        try {
            await checkJigyo({ ...this.jigyoKey, checkJisshibi: true });
        } catch (error) {
            this.showError(error);
            return;
        }
        this.isKanoubiOpen = true;
    }

    // 保存された従事可能日で置き換える（DB は登録時に更新する）
    handleKanoubiSave(event) {
        this.isKanoubiOpen = false;
        this.kanoubiDates = event.detail.kanoubiDates;
        this.isDirty = true;
    }

    // JUJ081 の初期表示エラーで閉じた場合はメッセージを表示する
    handleKanoubiClose(event) {
        this.isKanoubiOpen = false;
        const errorMessage = event.detail?.errorMessage;
        if (errorMessage) {
            this.showErrorMessage(errorMessage);
        }
    }

    // ========== 応募情報部の入力 ==========
    handleFormChange(event) {
        const field = event.target.dataset.field;
        this.form = { ...this.form, [field]: event.detail.value };
        this.isDirty = true;
    }

    // 全日程従事可能（ON の場合は従事可能曜日が入力不可になる）
    handleAllDaysChange(event) {
        this.form = { ...this.form, allDays: event.target.checked };
        this.isDirty = true;
    }

    handleKeikenChange(event) {
        this.form = { ...this.form, keiken: event.target.value };
        this.isDirty = true;
    }

    handleWeekdayChange(event) {
        const value = event.target.value;
        const isChecked = event.target.checked;

        let weekdays = [...this.form.weekdays];
        if (isChecked) {
            weekdays.push(value);
        } else {
            weekdays = weekdays.filter((day) => day !== value);
        }

        this.form = { ...this.form, weekdays };
        this.isDirty = true;
    }

    // スキル：項目名（data-field）ごとに選択値を保持する
    handleSkillChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;

        const skills = [...this.form.skills];
        const existingIndex = skills.findIndex((s) => s.field === field);
        if (existingIndex >= 0) {
            skills[existingIndex] = { ...skills[existingIndex], value };
        } else {
            skills.push({ field, value });
        }

        this.form = { ...this.form, skills };
        this.isDirty = true;
    }

    // ========== 登録 ==========
    async handleSaveClick() {
        this.clearMessages();
        const errors = [];
        const isValid = [
            this.validateJigyoKey(errors),
            this.validateJujisha(errors),
            this.validateForSave(errors)
        ].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        // 一括割当実行中は確認ダイアログの前にチェックする（登録処理内でも再チェックする）
        try {
            await checkJigyo({ ...this.jigyoKey, checkJisshibi: false });
        } catch (error) {
            this.showError(error);
            return;
        }
        if (!(await this.confirmDialog(MSG.CONFIRM_SAVE, TITLE.SAVE))) {
            return;
        }
        this.isLoading = true;
        try {
            // Apex の内部クラスを引数にできないため、JSON 文字列で渡す
            const result = await saveApplication({
                requestJson: JSON.stringify({
                    jigyoKey: this.jigyoKey,
                    jujishaNo: this.jujishaNo,
                    applicationId: this.applicationId,
                    systemModstamp: this.systemModstamp,
                    meisaiVersion: this.meisaiVersion,
                    form: this.form,
                    kanoubiDates: this.kanoubiDates
                })
            });
            if (result.uketukeNo != null) {
                this.lastUketukeNo = result.uketukeNo;
            }
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.SAVED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== 削除 ==========
    async handleDeleteClick() {
        this.clearMessages();
        if (!(await this.confirmDialog(MSG.CONFIRM_DELETE, TITLE.DELETE))) {
            return;
        }
        this.isLoading = true;
        try {
            await deleteApplication({ ...this.jigyoKey, jujishaNo: this.jujishaNo, systemModstamp: this.systemModstamp });
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.DELETED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== 全削除 ==========
    async handleDeleteAllClick() {
        this.clearMessages();
        const errors = [];
        if (!this.showErrorMessages(errors, this.validateJigyoKey(errors))) {
            return;
        }
        const msg1 =
            `${MSG.CONFIRM_DELETE_ALL_1}\n従事事業名:${this.jigyo.jigyoName}\n支部名:${this.jigyo.shibuName}\n` +
            `従事場所名:${this.basyoName}\n実施年度:${this.jigyoKey.jisiNendo}`;
        if (!(await this.confirmDialog(msg1, TITLE.DELETE_ALL)) ||
            !(await this.confirmDialog(MSG.CONFIRM_DELETE_ALL_2, TITLE.DELETE_ALL))) {
            return;
        }
        this.isLoading = true;
        try {
            await deleteAllApplications({ ...this.jigyoKey });
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.DELETED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== クリア・戻る・メニュー ==========
    async handleClearClick() {
        if (!(await this.confirmDiscard(TITLE.CLEAR))) {
            return;
        }
        // 従事事業メニューから遷移した場合は従事事業キー部も初期化する
        if (this.fromScreen === FROM_MENU) {
            this.jigyoKey = emptyJigyoKey();
            this.prevJigyoKey = emptyJigyoKey();
            this.basyoName = '';
            this.jigyo = {};
            this.lastUketukeNo = null;
        }
        this.resetJujishaAndApplication();
        this.clearMessages();
    }

    async handleBackClick() {
        if (!(await this.confirmDiscard(TITLE.BACK))) {
            return;
        }
        this.dispatchEvent(new CustomEvent('back'));
    }

    async handleMenuClick() {
        if (!(await this.confirmDiscard(TITLE.MENU))) {
            return;
        }
        this.dispatchEvent(new CustomEvent('showparentmenu'));
    }

    // 未登録の変更（応募情報部、従事可能日）が存在する場合のみ確認する
    async confirmDiscard(title) {
        return !this.isDirty || this.confirmDialog(MSG.CONFIRM_DISCARD, title);
    }

    // 読み込んだ応募を表示し、変更モードとする
    applyApplication(app) {
        this.applicationId = app.applicationId;
        this.systemModstamp = app.systemModstamp;
        this.meisaiVersion = app.meisaiVersion;
        this.uketukeNo = app.uketukeNo;
        this.form = { ...emptyForm(), ...app.form };
        this.kanoubiDates = app.kanoubiDates || [];
        this.isDirty = false;
    }

    // ========== 入力チェック ==========
    // 単項目のエラー（未入力・形式）は項目の下、それ以外は errors に追加して頭部に表示する。戻り値：true＝エラーなし

    // 従事事業キーの必須・実施年度の形式（項目の下）、従事事業の存在（頭部）
    validateJigyoKey(errors) {
        const isEntered = this.reportRequired(REQUIRED_JIGYO_KEY, this.jigyoKey);
        if (!isEntered) {
            // 従事事業基本情報から遷移した場合は入力欄がないため、頭部に表示する（防御用）
            if (this.isJigyoKeyReadonly) {
                errors.push(MSG.JIGYO_KEY_REQUIRED);
            }
            return false;
        }
        if (!this.validateNendoFormat(errors)) {
            return false;
        }
        if (!this.hasJigyo) {
            errors.push(MSG.JIGYO_NOT_FOUND);
            return false;
        }
        return true;
    }

    // 実施年度：半角数字4桁（入力不可の場合は頭部に表示する）
    validateNendoFormat(errors) {
        if (NENDO_PATTERN.test(this.jigyoKey.jisiNendo)) {
            return true;
        }
        const el = this.template.querySelector('[data-required][data-field="jisiNendo"]');
        if (el) {
            el.setCustomValidity(MSG.NENDO_FORMAT);
            el.reportValidity();
        } else {
            errors.push(MSG.NENDO_FORMAT);
        }
        return false;
    }

    validateJujishaNo() {
        return this.reportRequired(REQUIRED_JUJISHA, { jujishaNo: this.jujishaNo });
    }

    // 登録番号/相談員番号の必須（項目の下）、従事者の存在（頭部）
    validateJujisha(errors) {
        if (!this.validateJujishaNo()) {
            return false;
        }
        if (!this.hasJujisha) {
            errors.push(MSG.JUJISHA_NOT_FOUND);
            return false;
        }
        return true;
    }

    // 登録時のチェック
    validateForSave(errors) {
        const ctrl = this.inputControl;
        const f = this.form;
        const errorCount = errors.length;
        if (ctrl.requiredWeekday && !f.allDays && f.weekdays.length === 0) {
            errors.push(MSG.WEEKDAY_REQUIRED);
        }
        if (ctrl.requiredKanoubi && !this.kanoubiDates.some((k) => k.timeSlots && k.timeSlots.length > 0)) {
            errors.push(MSG.KANOUBI_REQUIRED);
        }
        // 値が空の科目は未選択とみなす
        if (ctrl.requiredSkill && !f.skills.some((s) => s.value)) {
            errors.push(MSG.SKILL_REQUIRED);
        }
        // 希望従事日数・連絡先（電話・FAX・Mail）は lightning-input の標準チェック（html の data-validate・pattern。入力不可の項目は対象外）
        const inputs = [...this.template.querySelectorAll('[data-validate]')];
        const isInputValid = inputs.reduce((ok, el) => el.reportValidity() && ok, true);
        return isInputValid && errors.length === errorCount;
    }

    // 単項目の必須チェック（html の data-required＝グループ名、data-field＝values のキー）
    reportRequired(group, values) {
        const labels = this.labels;
        this.template.querySelectorAll(`[data-required="${group}"]`).forEach((el) => {
            const field = el.dataset.field;
            el.setCustomValidity(values[field] ? '' : MSG.REQUIRED(labels[field]));
            el.reportValidity();
        });
        return Object.values(values).every((value) => !!value);
    }

    // 入力された項目の未入力エラーのみ消去する
    clearRequiredErrors(group, values) {
        this.template.querySelectorAll(`[data-required="${group}"]`).forEach((el) => {
            if (values[el.dataset.field]) {
                el.setCustomValidity('');
                el.reportValidity();
            }
        });
    }

    // ========== 初期化・モード ==========
    // 従事者情報部・応募情報部を初期化し、追加モードとする
    resetJujishaAndApplication() {
        this.jujishaNo = '';
        this.prevJujishaNo = '';
        this.jujisha = {};
        this.resetApplicationForm();
    }

    // 応募情報部を初期化し、追加モードとする
    resetApplicationForm() {
        this.uketukeNo = null;
        this.form = emptyForm();
        this.kanoubiDates = [];
        this.isDirty = false;
        this.toAddMode();
    }

    toAddMode() {
        this.applicationId = null;
        this.systemModstamp = null;
        this.meisaiVersion = null;
    }

    isSameJigyoKey(a, b) {
        return a.jujiJigyoNo === b.jujiJigyoNo && a.jujiBasyoNo === b.jujiBasyoNo && a.jisiNendo === b.jisiNendo;
    }

    // ========== 子画面・ダイアログ・メッセージ ==========
    // 確認ダイアログ（はい／いいえ）を表示し、「はい」の場合 true を返す
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

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ message, variant: 'success' }));
    }

    showErrorMessage(message) {
        this.headerMessages = [message];
    }

    // 入力チェックのエラーを頭部にまとめて表示する
    showErrorMessages(errors, isValid) {
        this.headerMessages = [...new Set(errors)]; // 同一文言は1件（html の key の重複防止）
        return isValid;
    }

    showError(error) {
        this.showErrorMessage(error?.body?.message || '予期しないエラーが発生しました。');
    }

    // ボタン押下時の開始時に呼び出す（フォーカスアウトでは頭部メッセージを消去しない）
    clearMessages() {
        this.headerMessages = [];
        this.template.querySelectorAll('[data-required]').forEach((el) => {
            el.setCustomValidity('');
            el.reportValidity();
        });
    }

    getFieldInfos(objectApiName) {
        const results = this.objectInfos?.data?.results || [];
        const info = results.find((r) => r.result && r.result.apiName === objectApiName);
        return info ? info.result.fields : {};
    }

    // ========== Getter ==========
    get hasHeaderMessages() {
        return this.headerMessages.length > 0;
    }

    // 希望従事日数のメッセージ（html の message-when-*）
    get kibouNissuRequiredMessage() {
        return MSG.REQUIRED(this.labels.kibouNissu);
    }

    get kibouNissuFormatMessage() {
        return MSG.KIBOU_NISSU_FORMAT;
    }

    get telPattern() {
        return TEL_PATTERN;
    }

    // 連絡先（固定電話・携帯電話・FAX）の形式エラーのメッセージ
    get telFormatMessages() {
        const labels = this.labels;
        return {
            telFixed: MSG.TEL_FORMAT(labels.telFixed),
            telMobile: MSG.TEL_FORMAT(labels.telMobile),
            fax: MSG.TEL_FORMAT(labels.fax)
        };
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

    get skillItems() {
        return SKILL_FIELDS.map(([field, label]) => {
            const skill = this.form.skills.find((s) => s.field === field);
            return { field, label, value: skill ? skill.value : null };
        });
    }

    get weekdayItems() {
        return WEEKDAYS.map((day) => ({ value: day, checked: this.form.weekdays.includes(day) }));
    }

    // ========== Getter（入力制御） ==========
    get hasJigyo() {
        return Object.keys(this.jigyo).length > 0;
    }

    get hasJujisha() {
        return Object.keys(this.jujisha).length > 0;
    }

    get inputControl() {
        return this.jigyo.inputControl || {};
    }

    get isChangeMode() {
        return this.applicationId != null;
    }

    get isDeleteDisabled() {
        return !this.isChangeMode;
    }

    // 従事事業基本情報から遷移した場合は従事事業キーが入力不可、検索ボタンが非活性
    get isJigyoKeyReadonly() {
        return this.fromScreen === FROM_JIGYO_INFO;
    }

    get isApplicationDisabled() {
        return !this.hasJigyo;
    }

    // 従事可能曜日：全日程従事可能が ON、または従事可能日が必須の場合は入力不可
    // ※ 従事可能曜日と従事可能日が同時に必須になることはない（事業の設定時にチェック済み）
    get isWeekdayDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredKanoubi || this.form.allDays;
    }

    get isWeekdayRequired() {
        return !!this.inputControl.requiredWeekday;
    }

    // 全日程従事可能：従事可能日が必須の場合は入力不可
    get isAllDaysDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredKanoubi;
    }

    // 従事可能日入力ボタン：従事可能曜日が必須の場合は使用不可
    get isKanoubiButtonDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredWeekday;
    }

    get isKibouNissuRequired() {
        return !!this.inputControl.requiredKibouNissu;
    }

    // スキル：必須、または任意入力フラグ＝許可の場合のみ入力可
    get isSkillRequired() {
        return !!this.inputControl.requiredSkill;
    }

    get isSkillDisabled() {
        return this.isApplicationDisabled || (!this.inputControl.requiredSkill && !this.inputControl.optionalSkill);
    }

    get skillOptions() {
        return SKILL_OPTIONS;
    }

    // スキル特記事項・主な著書、論文・相談科目：任意入力フラグ＝禁止の場合は入力不可
    get isSkillNoteDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalSkillNote;
    }

    get isChoshoDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalChosho;
    }

    get isSodanKamokuDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalSodanKamoku;
    }

    get keikenAri() {
        return KEIKEN_ARI;
    }

    get keikenNashi() {
        return KEIKEN_NASHI;
    }

    get isKeiKenAri() {
        return this.form.keiken === KEIKEN_ARI;
    }

    get isKeiKenNashi() {
        return this.form.keiken === KEIKEN_NASHI;
    }

    get kanoubiStatusLabel() {
        return this.kanoubiDates.length > 0 ? '指定済' : '未指定';
    }
}
