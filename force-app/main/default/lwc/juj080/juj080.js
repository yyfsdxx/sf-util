/**
 * JUJ080 従事事業応募登録
 * 設計書：JUJ080 処理詳細 v9・処理項目一覧
 * コメント中の番号は処理詳細の章番号に対応する。【要確認】は html・メタデータ・QA の確定後に修正する。
 *
 * ※ jujisha・jigyo は html から直接参照する（jujisha.name 等）ため null を代入しない。
 *   未取得時は空オブジェクト {} とし、判定には hasJujisha / hasJigyo を使用する。
 */
import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';

// ========== Apex（未実装のため一時的にコメントアウト。実装後は import を戻し、下のスタブを削除する）==========
// ※ Apex の引数：従事事業キーは3項目（jujiJigyoNo・jujiBasyoNo・jisiNendo）に分割して渡す。
//   登録リクエストは JSON 文字列（requestJson）で渡す。戻り値の構造は従来どおり。
// import getJigyo from '@salesforce/apex/JUJ080Controller.getJigyo';
// import getJujisha from '@salesforce/apex/JUJ080Controller.getJujisha';
// import loadApplication from '@salesforce/apex/JUJ080Controller.loadApplication';
// import checkJigyo from '@salesforce/apex/JUJ080Controller.checkJigyo';
// import saveApplication from '@salesforce/apex/JUJ080Controller.saveApplication';
// import deleteApplication from '@salesforce/apex/JUJ080Controller.deleteApplication';
// import deleteAllApplications from '@salesforce/apex/JUJ080Controller.deleteAllApplications';

// 共通の検索子画面（JUJ110・120・140）に渡す重なり順（本画面から直接開くため 1）
const SUB_SCREEN_LEVEL = 1;

// 共通の検索子画面の戻り値（数値で返る場合も文字列として扱う）
const toText = (value) => (value == null ? '' : String(value));

// 遷移元
const FROM_JIGYO_INFO = 'JIGYO_INFO'; // 従事事業基本情報
const FROM_MENU = 'MENU'; // 従事事業メニュー

// 【要確認 QA-20】メッセージ文言・ID。正式版ではカスタム表示ラベルに置き換える。
const MSG = {
    REQUIRED: 'この項目を入力してください。', // 単項目の未入力（項目の下に表示）
    JIGYO_KEY_REQUIRED: '従事事業No、従事場所No、実施年度を入力してください。', // 従事事業基本情報から遷移し、キーが欠けている場合のみ
    JIGYO_NOT_FOUND: '従事事業が存在しません。',
    JUJISHA_NOT_FOUND: '従事者が存在しません。', // WLP007-0009 相当
    WEEKDAY_REQUIRED: '従事可能曜日を選択してください。',
    KANOUBI_REQUIRED: '従事可能日を指定してください。',
    SKILL_REQUIRED: 'スキルを選択してください。',
    CONFIRM_OVERWRITE: '入力中の応募情報は破棄されます。よろしいですか？',
    CONFIRM_SAVE: '登録します。よろしいですか？',
    CONFIRM_DELETE: '削除します。よろしいですか？',
    CONFIRM_DELETE_ALL_2: '本当に全件削除してよろしいですか？',
    CONFIRM_DISCARD: '未登録の変更があります。破棄してよろしいですか？',
    SAVED: '登録しました。',
    DELETED: '削除しました。'
};

// 【要確認】従事経験の値
const KEIKEN_ARI = '1'; // 有
const KEIKEN_NASHI = '0'; // 無

// 【要確認】スキル評価の選択肢（選択リスト値の確定後に差し替える）
const SKILL_OPTIONS = [
    { label: '5(得意)', value: '5' },
    { label: '4', value: '4' },
    { label: '3', value: '3' },
    { label: '2', value: '2' },
    { label: '1(不得意)', value: '1' }
];

// 項目ラベルの取得元オブジェクト（【要確認】API 名確定後に置換）
const OBO_OBJECT = '従事事業応募__c'; // 従事事業応募
const JIGYO_OBJECT = '従事事業__c'; // 従事事業
const SODANIN_OBJECT = '相談員__c'; // 相談員マスタ（従事者情報部のラベル取得元）
const OFFICE_OBJECT = 'Account'; // 事務所・法人（支部コードのラベル取得元）

// 画面項目 → [オブジェクト, 項目名, 既定ラベル]。ラベルはメタデータから取得し、取得できない場合は既定ラベルを表示する
const LABEL_FIELDS = {
    jujiJigyoNo: [JIGYO_OBJECT, '従事事業No__c', '従事事業No.'],
    jigyoName: [JIGYO_OBJECT, '従事事業名__c', '従事事業名'],
    jisiNendo: [JIGYO_OBJECT, '実施年度__c', '実施年度'],
    shibuCode: [OFFICE_OBJECT, '支部コード__c', '支部コード'], // 従事事業・従事者情報部の両方で使用
    uketukeNo: [OBO_OBJECT, '受付番号__c', '受付番号'],
    kibouNissu: [OBO_OBJECT, '希望従事日数__c', '希望従事日数'],
    keiken: [OBO_OBJECT, '従事経験__c', '従事経験'],
    telFixed: [OBO_OBJECT, '連絡先_固定電話__c', '連絡先(固定電話)'],
    telMobile: [OBO_OBJECT, '連絡先_携帯電話__c', '連絡先(携帯電話)'],
    fax: [OBO_OBJECT, '連絡先_FAX__c', '連絡先(FAX)'],
    mail: [OBO_OBJECT, '連絡先_Mail__c', '連絡先(Mail)'],
    biko: [OBO_OBJECT, '備考__c', '備考'],
    skillNote: [OBO_OBJECT, 'スキル特記事項__c', 'スキル特記事項'],
    chosho: [OBO_OBJECT, '主な著書論文__c', '主な著書、論文'],
    sodanKamoku: [OBO_OBJECT, '相談科目__c', '相談科目'],
    // 従事者情報部（相談員マスタの項目ラベルを使用）
    jujishaName: [SODANIN_OBJECT, '氏名__c', '氏名'],
    jujishaFurigana: [SODANIN_OBJECT, 'フリガナ__c', 'フリガナ'],
    jujishaAddress: [SODANIN_OBJECT, '事務所住所__c', '事務所住所'],
    jujishaTel: [SODANIN_OBJECT, '事務所電話番号__c', '事務所電話番号'],
    jujishaFax: [SODANIN_OBJECT, '事務所FAX番号__c', '事務所FAX番号']
};

// スキル（8科目）：[項目名, 表示ラベル]。画面とサーバの受渡しは項目名をキーとする
// ※ 画面のラベルは項目ラベル（「スキル」接頭辞付き）と異なるため、メタデータから取得せず固定値とする
const SKILL_FIELDS = [
    ['スキル_所得税__c', '(所得税)'],
    ['スキル_会社法__c', '(会社法)'],
    ['スキル_法人税__c', '(法人税)'],
    ['スキル_財務会計__c', '(財務会計)'],
    ['スキル_資産税__c', '(資産税)'],
    ['スキル_譲渡山林__c', '(譲渡山林)'],
    ['スキル_消費税__c', '(消費税)'],
    ['スキル_贈与税__c', '(贈与税)']
];

// 従事可能曜日
const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

const emptyJigyoKey = () => ({ jujiJigyoNo: '', jujiBasyoNo: '', jisiNendo: '' });

// 必須チェックのグループ（html の data-required の値）
const REQUIRED_JIGYO_KEY = 'jigyoKey'; // 従事事業No・従事場所No・実施年度
const REQUIRED_JUJISHA = 'jujisha'; // 登録番号/相談員番号

// 応募情報部の初期値（処理項目一覧：従事経験＝有）
const emptyForm = () => ({
    telFixed: '', // 連絡先（固定電話）
    telMobile: '', // 連絡先（携帯電話）
    fax: '', // 連絡先（FAX）
    mail: '', // 連絡先（Mail）
    biko: '', // 備考
    allDays: false, // 全日程従事可能
    weekdays: [], // 従事可能曜日（'月'、'火' 等の配列）
    kibouNissu: null, // 希望従事日数
    keiken: KEIKEN_ARI, // 従事経験
    skills: [], // スキル（{ field: 項目名, value: 選択値 } の配列）
    skillNote: '', // スキル特記事項
    chosho: '', // 主な著書、論文
    sodanKamoku: '' // 相談科目（テキスト）
});

// ========== スタブ（Apex 実装後に削除）==========
// テスト用：従事事業No に 9999999 → 事業取得不可、登録番号に 9999999 → 従事者取得不可、
//          登録番号に 1111111 → 登録済みの応募あり（変更モード）
const STUB_JUJISHA = (jujishaNo) => ({
    jujishaType: 'MEMBER',
    jujishaNo,
    name: 'テスト 太郎',
    furigana: 'テスト タロウ',
    shibuCode: '001',
    shibuName: 'テスト支部',
    address: '東京都千代田区1-1-1',
    tel: '03-0000-0000',
    fax: '03-0000-0001'
});
const STUB_APPLICATION = {
    applicationId: 'a00000000000001AAA',
    uketukeNo: 1,
    systemModstamp: '2026-10-13T00:00:00.000Z',
    form: {
        telFixed: '03-1111-1111',
        mail: 'test@example.com',
        keiken: KEIKEN_ARI,
        weekdays: ['月', '水'],
        skills: [{ field: 'スキル_所得税__c', value: '5' }]
    },
    kanoubiDates: [
        { kanoubiDate: '2026-11-03', timeSlots: [{ startTime: '13:00', endTime: '15:00' }] },
        { kanoubiDate: '2026-12-01', timeSlots: [{ startTime: '10:00', endTime: '12:00' }] }
    ]
};
const getJigyo = async ({ jujiJigyoNo, jujiBasyoNo, jisiNendo }) => {
    const found = jujiJigyoNo && jujiBasyoNo && jisiNendo && jujiJigyoNo !== '9999999';
    return {
        basyoName: jujiBasyoNo ? `テスト場所${jujiBasyoNo}` : '',
        jigyo: found
            ? {
                  jigyoName: 'テスト事業',
                  shibuCode: '001',
                  shibuName: 'テスト支部',
                  lastUketukeNo: 3,
                  inputControl: {
                      requiredWeekday: false,
                      requiredKanoubi: false,
                      requiredKibouNissu: false,
                      requiredSkill: false,
                      optionalSkill: true,
                      optionalSkillNote: true,
                      optionalChosho: true,
                      optionalSodanKamoku: true
                  }
              }
            : null
    };
};
const getJujisha = async ({ jujishaNo }) => (jujishaNo === '9999999' ? null : STUB_JUJISHA(jujishaNo));
const loadApplication = async ({ applicationId, jujiJigyoNo, jujiBasyoNo, jisiNendo, jujishaNo }) => {
    // 応募情報検索からの戻り（応募ID指定）：固定の応募を返す
    if (applicationId) {
        return {
            jigyoKey: { jujiJigyoNo: '0000001', jujiBasyoNo: '0000000001', jisiNendo: '2026' },
            jujishaNo: '1111111',
            jujisha: STUB_JUJISHA('1111111'),
            application: STUB_APPLICATION
        };
    }
    // 応募情報表示（従事事業キー＋番号指定）
    if (jujishaNo === '9999999') {
        throw { body: { message: MSG.JUJISHA_NOT_FOUND } };
    }
    return {
        jigyoKey: { jujiJigyoNo, jujiBasyoNo, jisiNendo },
        jujishaNo,
        jujisha: STUB_JUJISHA(jujishaNo),
        application: jujishaNo === '1111111' ? STUB_APPLICATION : null
    };
};
const checkJigyo = async () => {};
const saveApplication = async ({ requestJson }) => {
    const req = JSON.parse(requestJson);
    if (!req.applicationId && req.jujishaNo === '1111111') {
        // 追加モードで登録済みの従事者を登録した場合（サーバ側 7.(3)③a のエラー）
        throw { body: { message: 'この従事者の応募情報は既に登録されています。応募情報表示ボタンで登録内容を表示してください。' } };
    }
    return { uketukeNo: 4 };
};
const deleteApplication = async () => {};
const deleteAllApplications = async () => {};
// ========== スタブ ここまで ==========

export default class Juj080 extends NavigationMixin(LightningElement) {
    fromScreen = FROM_MENU;

    // 従事事業キー部
    jigyoKey = emptyJigyoKey();
    prevJigyoKey = emptyJigyoKey();
    basyoName = ''; // 従事場所名
    jigyo = {}; // 取得した事業。{}＝未取得（null を代入しない）
    lastUketukeNo = null; // 最終受付番号

    // 従事者情報部
    jujishaNo = ''; // 登録番号/相談員番号
    prevJujishaNo = '';
    jujisha = {}; // {}＝未取得（html から jujisha.xxx を直接参照するため null を代入しない）
    uketukeNo = null; // 受付番号

    // 応募情報部
    applicationId = null; // null＝追加モード
    systemModstamp = null; // 応募のシステム更新日時（排他チェック用）
    form = emptyForm();
    kanoubiDates = []; // 保持中の従事可能日 [{ kanoubiDate: 'yyyy-MM-dd', timeSlots: [{ startTime, endTime }] }]

    isApplicationSearchOpen = false; // 応募情報検索（JUJ082）の表示有無
    isKanoubiOpen = false; // 従事可能日指定（JUJ081）の表示有無
    isJigyoSearchOpen = false; // 従事事業検索（JUJ110）の表示有無
    isBasyoSearchOpen = false; // 従事場所検索（JUJ120）の表示有無
    isJujishaSearchOpen = false; // 従事対象者検索（JUJ140）の表示有無
    subScreenLevel = SUB_SCREEN_LEVEL;
    isDirty = false; // 未登録の変更有無
    isLoading = false;
    headerMessages = []; // 画面頭部に表示するエラーメッセージ

    _initialized = false;

    // 項目ラベル取得用のオブジェクト情報
    objectApiNames = [OBO_OBJECT, JIGYO_OBJECT, SODANIN_OBJECT, OFFICE_OBJECT];
    @wire(getObjectInfos, { objectApiNames: '$objectApiNames' })
    objectInfos;

    // ========== 1. 初期表示 ==========
    // 【要確認】遷移パラメータの受渡し方式（暫定：URL state）
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef || this._initialized) {
            return;
        }
        this._initialized = true;
        this.initialize(pageRef.state || {});
    }

    async initialize(state) {
        // ① 初期値 ③ 追加モード
        this.resetJujishaAndApplication();
        // ② a. 従事事業基本情報から遷移：従事事業キーを設定し、事業の取得を行う
        if (state.c__from === FROM_JIGYO_INFO) {
            this.fromScreen = FROM_JIGYO_INFO;
            this.jigyoKey = {
                jujiJigyoNo: state.c__jujiJigyoNo || '',
                jujiBasyoNo: state.c__jujiBasyoNo || '',
                jisiNendo: state.c__jisiNendo || ''
            };
            await this.loadJigyo();
            this.prevJigyoKey = { ...this.jigyoKey };
        }
        // ② b. 従事事業メニューから遷移：入力制御は getter で行う
    }

    // ========== 2. 従事事業キー変更時 ==========
    handleJigyoKeyBlur(event) {
        const field = event.target.dataset.field; // jujiJigyoNo / jujiBasyoNo / jisiNendo
        this.jigyoKey = { ...this.jigyoKey, [field]: event.target.value };
        this.onJigyoKeyChanged();
    }

    // 従事事業検索（JUJ110）：検索条件は初期値なし。フォーカスアウトと同じ契機のため、メッセージは消去しない
    handleJigyoSearchClick() {
        this.isJigyoSearchOpen = true;
    }

    // 従事事業検索からの戻り：従事事業キー3項目を設定し、「2. 従事事業キー変更時」の処理を行う
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

    // 従事場所検索（JUJ120）
    handleBasyoSearchClick() {
        this.isBasyoSearchOpen = true;
    }

    // 従事場所検索からの戻り：従事場所No を設定し、「2. 従事事業キー変更時」の処理を行う
    handleBasyoSearchSelect(event) {
        this.isBasyoSearchOpen = false;
        const rec = event.detail.selectedRecord;
        this.jigyoKey = { ...this.jigyoKey, jujiBasyoNo: toText(rec.bashoNo) };
        this.onJigyoKeyChanged();
    }

    handleBasyoSearchClose() {
        this.isBasyoSearchOpen = false;
    }

    async onJigyoKeyChanged() {
        // 入力された項目の未入力エラーを消去する（頭部メッセージは次のボタン押下まで保持する）
        this.clearRequiredErrors(REQUIRED_JIGYO_KEY, this.jigyoKey);
        // (1) 事業の取得
        await this.loadJigyo();
        // (2) 3項目のいずれかが変わった場合、追加モードとし、応募情報部（受付番号・従事可能日を含む）を初期化する
        //     登録番号/相談員番号・従事者情報部は保持する
        if (!this.isSameJigyoKey(this.jigyoKey, this.prevJigyoKey)) {
            this.resetApplicationForm();
        }
        this.prevJigyoKey = { ...this.jigyoKey };
    }

    // 2.(1) 事業の取得
    async loadJigyo() {
        const { jujiJigyoNo, jujiBasyoNo, jisiNendo } = this.jigyoKey;
        // 従事場所No が変わっていない場合、従事場所名は再設定しない（表示のちらつき防止）
        const isBasyoChanged = jujiBasyoNo !== this.prevJigyoKey.jujiBasyoNo;
        if (isBasyoChanged) {
            this.basyoName = '';
        }
        // 従事事業キーが変わっていない場合（フォーカスアウトのみ）は、取得結果が返るまで現在の表示を保持する（表示のちらつき防止）
        // 変わった場合は、取得中に旧事業の設定で入力・登録できないよう、先に空白とする
        if (!this.isSameJigyoKey(this.jigyoKey, this.prevJigyoKey)) {
            this.jigyo = {};
            this.lastUketukeNo = null;
        }
        // ① 従事場所No 入力時は従事場所名を取得、② 3項目すべて入力時は事業を取得。いずれも該当しない場合は呼び出さない
        if (!jujiBasyoNo && !(jujiJigyoNo && jisiNendo)) {
            return;
        }
        try {
            // 戻り値：{ basyoName, jigyo: { jigyoName, shibuCode, shibuName, lastUketukeNo, inputControl } | null }
            const result = await getJigyo({ ...this.jigyoKey });
            if (isBasyoChanged) {
                this.basyoName = result.basyoName || '';
            }
            this.jigyo = result.jigyo || {};
            this.lastUketukeNo = result.jigyo ? result.jigyo.lastUketukeNo : null;
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 3. 登録番号/相談員番号の変更時 ==========
    handleJujishaNoBlur(event) {
        this.jujishaNo = event.target.value;
        this.onJujishaNoChanged();
    }

    // 従事対象者検索（JUJ140）
    handleJujishaSearchClick() {
        this.isJujishaSearchOpen = true;
    }

    // 従事対象者検索からの戻り：番号（会員は登録番号、相談員は相談員番号）を設定し、「3. 番号の変更時」の処理を行う
    handleJujishaSearchSelect(event) {
        this.isJujishaSearchOpen = false;
        const rec = event.detail.selectedRecord;
        this.jujishaNo = toText(rec.startNo); // 登録番号があれば登録番号、なければ相談員番号
        this.onJujishaNoChanged();
    }

    handleJujishaSearchClose() {
        this.isJujishaSearchOpen = false;
    }

    async onJujishaNoChanged() {
        // 入力された場合は未入力エラーを消去する（頭部メッセージは次のボタン押下まで保持する）
        this.clearRequiredErrors(REQUIRED_JUJISHA, { jujishaNo: this.jujishaNo });
        // 変更前の値と同じ場合は何もしない
        if (this.jujishaNo === this.prevJujishaNo) {
            return;
        }
        this.prevJujishaNo = this.jujishaNo;
        // (1) 従事者の取得
        await this.loadJujisha();
        // (2) ① 応募情報部の入力内容は保持し、受付番号・従事可能日のみ初期化する ② 追加モードとする
        // ※ 登録済みの応募がある従事者かどうかは登録時にサーバ側でチェックする（7.(3)③a）
        this.kanoubiDates = [];
        this.uketukeNo = null;
        this.toAddMode();
    }

    // 3.(1) 従事者の取得（取得できない場合はエラーとせず空白表示）
    async loadJujisha() {
        this.jujisha = {};
        if (!this.jujishaNo) {
            return; // ①
        }
        try {
            // 戻り値：{ jujishaType, jujishaNo, name, furigana, shibuCode, shibuName, address, tel, fax } | null
            const result = await getJujisha({ jujishaNo: this.jujishaNo });
            this.jujisha = result || {};
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 4. 応募情報表示ボタン押下時 ==========
    async handleShowApplicationClick() {
        this.clearMessages();
        // (1) 入力チェック ①②（③ 従事者の存在チェックはサーバ側で行う）
        // ※ エラーはまとめて表示するため、すべてのチェックを行ってから判定する
        const errors = [];
        const isValid = [this.validateJujishaNo(), this.validateJigyoKey(errors)].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        // (2) 上書き確認
        if (this.isDirty && !(await this.confirmDialog(MSG.CONFIRM_OVERWRITE))) {
            return;
        }
        try {
            // 戻り値：{ jujisha, application | null }
            const result = await loadApplication({ ...this.jigyoKey, jujishaNo: this.jujishaNo });
            // (3) ① 初期化した後、従事者を表示する
            this.resetApplicationForm();
            this.jujisha = result.jujisha || {};
            this.prevJujishaNo = this.jujishaNo;
            // ② 応募あり → 応募情報の読込（変更モード）、応募なし → 追加モード
            if (result.application) {
                this.applyApplication(result.application);
            }
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 応募情報検索ボタン押下時：応募情報検索（JUJ082）を表示する ==========
    handleApplicationSearchClick() {
        this.clearMessages();
        this.isApplicationSearchOpen = true;
    }

    // 応募情報検索の閉じる
    handleApplicationSearchClose() {
        this.isApplicationSearchOpen = false;
    }

    // ========== 5. 応募情報検索からの戻り時（応募行の選択） ==========
    async handleApplicationSearchSelect(event) {
        this.isApplicationSearchOpen = false;
        const { applicationId } = event.detail;
        try {
            // 戻り値：{ jigyoKey, jujishaNo, jujisha, application }
            const res = await loadApplication({ applicationId });
            // ① 従事事業メニューから遷移した場合、選択された応募の従事事業キーを設定し、事業の取得を行う
            if (this.fromScreen === FROM_MENU) {
                this.jigyoKey = { ...res.jigyoKey };
                await this.loadJigyo();
                this.prevJigyoKey = { ...this.jigyoKey };
            }
            // ② 応募情報の読込を行い、変更モードとする
            this.jujishaNo = res.jujishaNo;
            this.prevJujishaNo = res.jujishaNo;
            this.jujisha = res.jujisha || {};
            this.applyApplication(res.application);
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 6. 従事可能日入力ボタン押下時 ==========
    async handleKanoubiInputClick() {
        this.clearMessages();
        // (1) ① 従事事業キー・従事者の確定チェック（エラーはまとめて表示する）
        const errors = [];
        const isValid = [this.validateJigyoKey(errors), this.validateJujisha(errors)].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        // (1) ②③ 実施日の有無・一括割当実行中（サーバ側でチェック）
        try {
            await checkJigyo({ ...this.jigyoKey, checkJisshibi: true });
        } catch (error) {
            this.showError(error);
            return;
        }
        // (2) ① 従事可能日指定（JUJ081）を表示する（従事事業キー・番号・保持中の従事可能日を html で引き渡す）
        this.isKanoubiOpen = true;
    }

    // (2) ② a. 保存：戻り値の従事可能日で保持内容を置き換える ③ DB は更新しない
    handleKanoubiSave(event) {
        this.isKanoubiOpen = false;
        this.kanoubiDates = event.detail.kanoubiDates;
        this.isDirty = true;
    }

    // (2) ② b. 閉じる：何もしない（JUJ081 の初期表示エラーで閉じた場合はメッセージを表示する）
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

    // 全日程従事可能（ON：従事可能曜日を入力不可）
    handleAllDaysChange(event) {
        this.form = { ...this.form, allDays: event.target.checked };
        this.isDirty = true;
    }

    // 従事経験：ラジオボタンの選択値を設定する
    handleKeikenChange(event) {
        this.form = { ...this.form, keiken: event.target.value };
        this.isDirty = true;
    }

    // 従事可能曜日：チェック ON で配列に追加、OFF で配列から除外する
    handleWeekdayChange(event) {
        const value = event.target.value; // '月'、'火' 等
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

    // スキル：項目名（コンボボックスの data-field）ごとに選択値を保持する。既存の科目は値を更新、なければ追加する
    handleSkillChange(event) {
        const field = event.target.dataset.field; // 例：'スキル_所得税__c'
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

    // ========== 7. 登録ボタン押下時 ==========
    async handleSaveClick() {
        this.clearMessages();
        // (1) 入力チェック ①②③（④ 一括割当実行中はサーバ側でチェック）。エラーはまとめて表示する
        const errors = [];
        const isValid = [
            this.validateJigyoKey(errors),
            this.validateJujisha(errors),
            this.validateForSave(errors)
        ].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        // (1) ④ 一括割当実行中（サーバ側でチェック。登録処理内でも再チェックする）
        try {
            await checkJigyo({ ...this.jigyoKey, checkJisshibi: false });
        } catch (error) {
            this.showError(error);
            return;
        }
        // (2) 登録確認
        if (!(await this.confirmDialog(MSG.CONFIRM_SAVE))) {
            return;
        }
        this.isLoading = true;
        try {
            // (3) 登録処理。戻り値：{ uketukeNo }（採番しなかった場合は null）
            // 登録リクエストは JSON 文字列で渡す（Apex の内部クラスを引数に使用できないため）
            const result = await saveApplication({
                requestJson: JSON.stringify({
                    jigyoKey: this.jigyoKey,
                    jujishaNo: this.jujishaNo,
                    applicationId: this.applicationId,
                    systemModstamp: this.systemModstamp,
                    form: this.form,
                    kanoubiDates: this.kanoubiDates
                })
            });
            // (4) ① 採番した場合のみ最終受付番号を更新する
            if (result.uketukeNo != null) {
                this.lastUketukeNo = result.uketukeNo;
            }
            // ② 従事事業キー部は保持し、それ以外を初期化して追加モードとする
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.SAVED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== 8. 削除ボタン押下時 ==========
    async handleDeleteClick() {
        this.clearMessages();
        // (1) 削除確認
        if (!(await this.confirmDialog(MSG.CONFIRM_DELETE))) {
            return;
        }
        this.isLoading = true;
        try {
            // (2) 削除処理（画面表示時のシステム更新日時を渡し、排他チェックを行う）
            await deleteApplication({ ...this.jigyoKey, jujishaNo: this.jujishaNo, systemModstamp: this.systemModstamp });
            // (3) 画面反映
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.DELETED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== 9. 全削除ボタン押下時 ==========
    async handleDeleteAllClick() {
        this.clearMessages();
        // (1) 入力チェック
        const errors = [];
        if (!this.showErrorMessages(errors, this.validateJigyoKey(errors))) {
            return;
        }
        // (2) 削除確認（2回）
        const msg1 =
            `従事事業名：${this.jigyo.jigyoName}\n支部名：${this.jigyo.shibuName}\n` +
            `従事場所名：${this.basyoName}\n実施年度：${this.jigyoKey.jisiNendo}\n` +
            'の応募情報をすべて削除します。よろしいですか？';
        if (!(await this.confirmDialog(msg1)) || !(await this.confirmDialog(MSG.CONFIRM_DELETE_ALL_2))) {
            return;
        }
        this.isLoading = true;
        try {
            // (3) 削除処理
            await deleteAllApplications({ ...this.jigyoKey });
            // (4) 画面反映
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.DELETED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== 10. クリア・戻る・メニューボタン押下時 ==========
    async handleClearClick() {
        if (!(await this.confirmDiscard())) {
            return;
        }
        // ① b. 従事事業メニューから遷移した場合：従事事業キー部も初期化する
        if (this.fromScreen === FROM_MENU) {
            this.jigyoKey = emptyJigyoKey();
            this.prevJigyoKey = emptyJigyoKey();
            this.basyoName = '';
            this.jigyo = {};
            this.lastUketukeNo = null;
        }
        // ① a・b 共通
        this.resetJujishaAndApplication();
        this.clearMessages();
    }

    async handleBackClick() {
        if (!(await this.confirmDiscard())) {
            return;
        }
        // ② 【要確認】遷移元への戻り方
        window.history.back();
    }

    async handleMenuClick() {
        if (!(await this.confirmDiscard())) {
            return;
        }
        // ③ 【要確認】JUJ010 のページ API 名
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'JUJ010' }
        });
    }

    // 10.(1) 未登録の変更がある場合のみ確認する
    async confirmDiscard() {
        return !this.isDirty || this.confirmDialog(MSG.CONFIRM_DISCARD);
    }

    // ========== 11. 共通処理 ==========
    // 11.(1) 応募情報の読込（② 表示 ③ システム更新日時を保持 → 変更モード）
    applyApplication(app) {
        this.applicationId = app.applicationId;
        this.systemModstamp = app.systemModstamp;
        this.uketukeNo = app.uketukeNo;
        this.form = { ...emptyForm(), ...app.form };
        this.kanoubiDates = app.kanoubiDates || [];
        this.isDirty = false;
    }

    // ※ チェック方針：単項目のエラー（未入力・形式）は各項目の下に表示し、それ以外は errors に追加して頭部に表示する。
    //   戻り値はチェック結果（true：エラーなし）。

    // 11.(2) ① 従事事業キー：未入力は各項目の下、3項目入力済みで事業が取得できない場合は頭部に表示する
    validateJigyoKey(errors) {
        const isEntered = this.reportRequired(REQUIRED_JIGYO_KEY, this.jigyoKey);
        if (!isEntered) {
            // 従事事業基本情報から遷移した場合は入力欄がないため、頭部に表示する
            if (this.isJigyoKeyReadonly) {
                errors.push(MSG.JIGYO_KEY_REQUIRED);
            }
            return false;
        }
        if (!this.hasJigyo) {
            errors.push(MSG.JIGYO_NOT_FOUND);
            return false;
        }
        return true;
    }

    // 11.(2) ② a 登録番号/相談員番号の未入力（項目の下に表示）
    validateJujishaNo() {
        return this.reportRequired(REQUIRED_JUJISHA, { jujishaNo: this.jujishaNo });
    }

    // 11.(2) ② 従事者：未入力は項目の下、入力済みで従事者が取得できない場合は頭部に表示する
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

    // 7.(1) ② 必須入力フラグ ③ 電話番号・メールアドレスの形式
    validateForSave(errors) {
        const ctrl = this.inputControl;
        const f = this.form;
        const errorCount = errors.length;
        if (ctrl.requiredWeekday && !f.allDays && f.weekdays.length === 0) {
            errors.push(MSG.WEEKDAY_REQUIRED); // a
        }
        if (ctrl.requiredKanoubi && this.kanoubiDates.length === 0) {
            errors.push(MSG.KANOUBI_REQUIRED); // b
        }
        // d. スキルが1科目以上選択されていること（値が空の科目は未選択とみなす）（QA-21）
        if (ctrl.requiredSkill && !f.skills.some((s) => s.value)) {
            errors.push(MSG.SKILL_REQUIRED);
        }
        // c. 希望従事日数（required 属性）・③ 電話番号・メールアドレス（type/pattern）：単項目チェックのため各項目の下に表示する
        // ※ html 側の lightning-input に data-validate を設定する（入力不可の項目はチェックされない）
        const inputs = [...this.template.querySelectorAll('[data-validate]')];
        const isInputValid = inputs.reduce((ok, el) => el.reportValidity() && ok, true);
        return isInputValid && errors.length === errorCount;
    }

    // 単項目の必須チェック：values のうち未入力の項目の下にエラーを表示する（入力済みの項目はエラーを消去する）
    // html 側の lightning-input に data-required（グループ名）・data-field（values のキー）を設定する
    reportRequired(group, values) {
        this.template.querySelectorAll(`[data-required="${group}"]`).forEach((el) => {
            el.setCustomValidity(values[el.dataset.field] ? '' : MSG.REQUIRED);
            el.reportValidity();
        });
        return Object.values(values).every((value) => !!value);
    }

    // 入力された項目の未入力エラーを消去する（未入力のままの項目はエラーを保持する）
    clearRequiredErrors(group, values) {
        this.template.querySelectorAll(`[data-required="${group}"]`).forEach((el) => {
            if (values[el.dataset.field]) {
                el.setCustomValidity('');
                el.reportValidity();
            }
        });
    }

    // 登録番号/相談員番号・従事者情報部・応募情報部を初期化し、追加モードとする
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

    // 追加モード：保持している応募IDを破棄する
    toAddMode() {
        this.applicationId = null;
        this.systemModstamp = null;
    }

    isSameJigyoKey(a, b) {
        return a.jujiJigyoNo === b.jujiJigyoNo && a.jujiBasyoNo === b.jujiBasyoNo && a.jisiNendo === b.jisiNendo;
    }

    // ========== 子画面・ダイアログ・メッセージ ==========
    confirmDialog(message) {
        return LightningConfirm.open({ message, variant: 'headerless' });
    }

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ message, variant: 'success' }));
    }

    // エラーメッセージを画面頭部に表示する（サーバ側のエラー等、1件の場合）
    showErrorMessage(message) {
        this.headerMessages = [message];
    }

    // 入力チェックのエラーを画面頭部にまとめて表示する。戻り値：チェック結果（true：エラーなし）
    showErrorMessages(errors, isValid) {
        this.headerMessages = [...new Set(errors)]; // 同一文言は1件とする（html の key が重複しないよう）
        return isValid;
    }

    // AuraHandledException のメッセージを表示する
    showError(error) {
        this.showErrorMessage(error?.body?.message || '予期しないエラーが発生しました。');
    }

    // 画面頭部のエラーメッセージ・項目の未入力エラーを消去する（各ボタン押下時の開始時に呼び出す）
    // ※ フォーカスアウト（従事事業キー・登録番号/相談員番号の変更）ではチェックを行わないため、頭部メッセージは消去しない
    clearMessages() {
        this.headerMessages = [];
        this.template.querySelectorAll('[data-required]').forEach((el) => {
            el.setCustomValidity('');
            el.reportValidity();
        });
    }

    // 項目ラベル取得：指定オブジェクトの項目情報（未取得時は空オブジェクト）
    getFieldInfos(objectApiName) {
        const results = this.objectInfos?.data?.results || [];
        const info = results.find((r) => r.result && r.result.apiName === objectApiName);
        return info ? info.result.fields : {};
    }

    // ========== Getter（メッセージ） ==========
    get hasHeaderMessages() {
        return this.headerMessages.length > 0;
    }

    // ========== Getter（項目ラベル） ==========
    // 画面項目のラベル（メタデータから取得。取得できない場合は既定ラベル）
    get labels() {
        const labels = {};
        Object.entries(LABEL_FIELDS).forEach(([key, [objectApiName, field, defaultLabel]]) => {
            const fieldInfo = this.getFieldInfos(objectApiName)[field];
            labels[key] = fieldInfo ? fieldInfo.label : defaultLabel;
        });
        return labels;
    }

    // スキル：8科目の表示用リスト（項目名・ラベル・選択値）
    get skillItems() {
        return SKILL_FIELDS.map(([field, label]) => {
            const skill = this.form.skills.find((s) => s.field === field);
            return { field, label, value: skill ? skill.value : null };
        });
    }

    // 従事可能曜日：7曜日の表示用リスト（値・選択状態）
    get weekdayItems() {
        return WEEKDAYS.map((day) => ({ value: day, checked: this.form.weekdays.includes(day) }));
    }

    // ========== Getter（処理項目一覧の入力制御） ==========
    // 事業・従事者の取得有無（未取得時は空オブジェクト {}）
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

    // 削除ボタン：追加モードでは使用不可
    get isDeleteDisabled() {
        return !this.isChangeMode;
    }

    // 従事事業キー：従事事業基本情報から遷移した場合は入力不可
    get isJigyoKeyReadonly() {
        return this.fromScreen === FROM_JIGYO_INFO;
    }

    // 従事事業キー未確定 → 応募情報部をすべて入力不可
    get isApplicationDisabled() {
        return !this.hasJigyo;
    }

    // 従事可能曜日：必須入力フラグ（従事可能日）＝1 または全日程従事可能 ON の場合は入力不可
    // ※ 必須入力フラグ（従事可能曜日）と（従事可能日）が同時に 1 になることはない（事業側でチェック済み）
    get isWeekdayDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredKanoubi || this.form.allDays;
    }

    get isWeekdayRequired() {
        return !!this.inputControl.requiredWeekday;
    }

    // 全日程従事可能：必須入力フラグ（従事可能日）＝1 の場合は入力不可
    get isAllDaysDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredKanoubi;
    }

    // 従事可能日入力ボタン：必須入力フラグ（従事可能曜日）＝1 の場合は使用不可
    get isKanoubiButtonDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredWeekday;
    }

    get isKibouNissuRequired() {
        return !!this.inputControl.requiredKibouNissu;
    }

    // スキル：必須入力フラグ＝1 → 必須、任意入力フラグ＝1 → 入力可、いずれも 0 → 入力不可（QA-21）
    get isSkillRequired() {
        return !!this.inputControl.requiredSkill;
    }

    get isSkillDisabled() {
        return this.isApplicationDisabled || (!this.inputControl.requiredSkill && !this.inputControl.optionalSkill);
    }

    // スキル：コンボボックスの選択肢
    get skillOptions() {
        return SKILL_OPTIONS;
    }

    // スキル特記事項・主な著書、論文・相談科目：任意入力フラグ＝1 → 入力可、0 → 入力不可（QA-21）
    get isSkillNoteDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalSkillNote;
    }

    get isChoshoDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalChosho;
    }

    get isSodanKamokuDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalSodanKamoku;
    }

    // 従事経験：ラジオボタンの選択状態
    get isKeiKenAri() {
        return this.form.keiken === KEIKEN_ARI;
    }

    get isKeiKenNashi() {
        return this.form.keiken === KEIKEN_NASHI;
    }

    // 従事可能個別日：1件以上なら「指定済」、0件なら「未指定」
    get kanoubiStatusLabel() {
        return this.kanoubiDates.length > 0 ? '指定済' : '未指定';
    }
}
