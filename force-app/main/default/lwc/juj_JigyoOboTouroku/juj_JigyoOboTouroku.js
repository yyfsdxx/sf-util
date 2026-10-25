/**
 * JUJ080 従事事業応募登録
 * 設計書：機能設計書 処理詳細（JUJ080／081／082 共通シート）
 * コメント中の番号は「1.画面アクション No.」「3.表示ラベル No.」「4.入力チェック No.」「5.データ更新 (n)」に対応する。
 * 【要確認】は html・メタデータ・QA の確定後に修正する。
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
// import getJigyo from '@salesforce/apex/Juj_JigyoOboTourokuController.getJigyo';
// import getJujisha from '@salesforce/apex/Juj_JigyoOboTourokuController.getJujisha';
// import loadApplication from '@salesforce/apex/Juj_JigyoOboTourokuController.loadApplication';
// import checkJigyo from '@salesforce/apex/Juj_JigyoOboTourokuController.checkJigyo';
// import saveApplication from '@salesforce/apex/Juj_JigyoOboTourokuController.saveApplication';
// import deleteApplication from '@salesforce/apex/Juj_JigyoOboTourokuController.deleteApplication';
// import deleteAllApplications from '@salesforce/apex/Juj_JigyoOboTourokuController.deleteAllApplications';

// 共通の検索子画面（JUJ110・120・140）に渡す重なり順（本画面から直接開くため 1）
const SUB_SCREEN_LEVEL = 1;

// 共通の検索子画面の戻り値（数値で返る場合も文字列として扱う）
const toText = (value) => (value == null ? '' : String(value));

// 遷移元
const FROM_JIGYO_INFO = 'JIGYO_INFO'; // 従事事業基本情報
const FROM_MENU = 'MENU'; // 従事事業メニュー

// メッセージ。末尾は 4.入力チェックの No.【要確認 QA-20】正式版ではカスタム表示ラベルに置き換える。
const MSG = {
    REQUIRED: (label) => `${label}は必須入力項目です。`, // No.1〜3・6・10（項目の下に表示）
    NENDO_FORMAT: '実施年度は4桁の半角数字（西暦）で入力してください。', // No.4（項目の下に表示）
    KIBOU_NISSU_FORMAT: '希望従事日数は3桁以内の1以上の半角数字で入力してください。', // No.10（項目の下に表示）
    JIGYO_KEY_REQUIRED: '従事事業No、従事場所No、実施年度を入力してください。', // 従事事業基本情報から遷移し、キーが欠けている場合のみ（防御用）
    JIGYO_NOT_FOUND: '従事事業が存在しません。', // No.5
    JUJISHA_NOT_FOUND: '従事者が存在しません。', // No.7（WLP007-0009 相当）
    WEEKDAY_REQUIRED: '従事可能曜日を選択してください。', // No.8
    KANOUBI_REQUIRED: '従事可能日を指定してください。', // No.9
    SKILL_REQUIRED: 'スキルを選択してください。', // No.11
    CONFIRM_OVERWRITE: '入力中の応募情報は破棄されます。よろしいですか？',
    CONFIRM_SAVE: '登録します。よろしいですか？',
    CONFIRM_DELETE: '削除します。よろしいですか？',
    CONFIRM_DELETE_ALL_1: '以下の事業に関する応募情報を全て削除します。この操作は取り消すことは出来ません', // 画面イメージ(ToBe)の文言
    CONFIRM_DELETE_ALL_2: '応募情報を全て削除します。本当によろしいですか？', // 画面イメージ(ToBe)の文言
    CONFIRM_DISCARD: '未登録の変更があります。破棄してよろしいですか？',
    SAVED: '登録しました。',
    DELETED: '削除しました。'
};

// 確認ダイアログのタイトル：押下したボタン名＋「確認」
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

// 従事経験の値（選択リスト 有;無）
const KEIKEN_ARI = '有';
const KEIKEN_NASHI = '無';

// スキル評価の選択肢（選択リスト 1〜5）
const SKILL_OPTIONS = [
    { label: '5(得意)', value: '5' },
    { label: '4', value: '4' },
    { label: '3', value: '3' },
    { label: '2', value: '2' },
    { label: '1(不得意)', value: '1' }
];

// 項目ラベルの取得元オブジェクト（3.表示ラベルの「項目ラベル取得元」）
const OBO_OBJECT = 'Juji_Jigyo_Oubo__c'; // 従事事業応募
const JIGYO_OBJECT = 'Juji_Jigyo__c'; // 従事事業
const BASYO_OBJECT = 'Juji_Basyo_Master__c'; // 従事場所マスタ
const SODANIN_OBJECT = 'Soudanin_Master__c'; // 相談員マスタ（従事者情報部のラベル取得元）
const OFFICE_OBJECT = 'Account'; // 事務所・法人（支部コード・支部名のラベル取得元）

// 画面項目 → [オブジェクト, 項目名, 既定ラベル]。ラベルはメタデータから取得し、取得できない場合は既定ラベルを表示する
const LABEL_FIELDS = {
    jujiJigyoNo: [JIGYO_OBJECT, 'Juji_Juji_Jigyo_No__c', '従事事業No.'],
    jigyoName: [JIGYO_OBJECT, 'Juji_Juji_Jigyo_Name__c', '従事事業名'],
    jisiNendo: [JIGYO_OBJECT, 'Juji_Jisi_Nendo__c', '実施年度'],
    jujiBasyoNo: [BASYO_OBJECT, 'JujM_Juji_Basyo_No__c', '従事場所No.'],
    basyoName: [BASYO_OBJECT, 'JujM_Juji_Basyo_Name__c', '従事場所名'],
    shibuCode: [OFFICE_OBJECT, 'Jims_Sibu_Code__c', '支部コード'], // 従事事業キー部・従事者情報部の両方で使用
    shibuName: [OFFICE_OBJECT, 'Jims_Sibu_Name__c', '支部名'], // 同上
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
    // 従事者情報部（相談員マスタの項目ラベルを使用）
    jujishaName: [SODANIN_OBJECT, 'SouM_Sodanin_Name__c', '氏名'],
    jujishaFurigana: [SODANIN_OBJECT, 'SouM_Sodanin_Name_Furigana__c', 'フリガナ'],
    jujishaAddress: [SODANIN_OBJECT, 'SouM_Jimusyo_Jusyo__c', '事務所住所'],
    jujishaTel: [SODANIN_OBJECT, 'SouM_Jimusyo_Tel_No__c', '事務所電話番号'],
    jujishaFax: [SODANIN_OBJECT, 'SouM_Jimusyo_Fax_No__c', '事務所FAX番号']
};

// 項目ラベル取得元が「固定」の項目
const FIXED_LABELS = {
    jujishaNo: '登録番号/相談員番号'
};

// スキル（8科目）：[項目名, 表示ラベル]。画面とサーバの受渡しは項目名をキーとする（並びは画面の表示順）
// ※ 画面のラベルは項目ラベルと異なるため、メタデータから取得せず固定値とする（3.表示ラベル No.34）
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

// 従事可能曜日
const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

const emptyJigyoKey = () => ({ jujiJigyoNo: '', jujiBasyoNo: '', jisiNendo: '' });

// 必須チェックのグループ（html の data-required の値）
const REQUIRED_JIGYO_KEY = 'jigyoKey'; // 従事事業No・従事場所No・実施年度
const REQUIRED_JUJISHA = 'jujisha'; // 登録番号/相談員番号

// 応募情報部の初期値（3.表示ラベル No.22〜37：従事経験＝有）
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
// ■ 遷移元の切替（ローカルプレビュー用）
//   従事事業メニューから：{}（遷移パラメータなし。従事事業キーは入力可）
//   従事事業基本情報から：下のコメントを外す（事業A のキーを引き継ぎ、入力不可）
const STUB_PAGE_STATE = {};
// const STUB_PAGE_STATE = { c__from: FROM_JIGYO_INFO, c__jujiJigyoNo: '0000001', c__jujiBasyoNo: '0000000001', c__jisiNendo: '2026' };
//
// ■ テストデータ（JUJ082 のスタブと同じ応募ID・番号）
//   事業A：0000001 / 0000000001 / 2026（応募 3件：佐藤 花子・山田 太郎・山田 一郎）
//   事業B：0000002 / 0000000002 / 2026（応募 1件：山田 太郎）
//   番号：1000001 山田 太郎・1000002 佐藤 花子（会員）、9000001 山田 一郎（相談員）、9999999 → 従事者なし、その他 → 会員「テスト 太郎」
//   上記以外の事業キー → 事業なし
const STUB_JIGYO_LIST = [
    { key: { jujiJigyoNo: '0000001', jujiBasyoNo: '0000000001', jisiNendo: '2026' }, jigyoName: 'テスト事業A', shibuCode: '001', shibuName: '東支部', basyoName: 'テスト場所A', lastUketukeNo: 2 },
    { key: { jujiJigyoNo: '0000002', jujiBasyoNo: '0000000002', jisiNendo: '2026' }, jigyoName: 'テスト事業B', shibuCode: '002', shibuName: '西支部', basyoName: 'テスト場所B', lastUketukeNo: 1 }
];
const STUB_JUJISHA_LIST = {
    1000001: { jujishaType: 'MEMBER', name: '山田 太郎', furigana: 'ヤマダ タロウ', shibuCode: '001', shibuName: '東支部', address: '大阪府大阪市1-1-1', tel: '06-0000-0001', fax: '06-0000-0101' },
    1000002: { jujishaType: 'MEMBER', name: '佐藤 花子', furigana: 'サトウ ハナコ', shibuCode: '002', shibuName: '西支部', address: '大阪府堺市2-2-2', tel: '072-000-0002', fax: '072-000-0102' },
    9000001: { jujishaType: 'SODANIN', name: '山田 一郎', furigana: 'ヤマダ イチロウ', shibuCode: '', shibuName: '', address: '京都府京都市3-3-3', tel: '075-000-0003', fax: '' }
};
const STUB_APPLICATIONS = [
    {
        jigyoKey: STUB_JIGYO_LIST[0].key,
        jujishaNo: '1000002',
        application: {
            applicationId: 'a00000000000001AAA',
            uketukeNo: 1,
            systemModstamp: '2026-10-01T01:00:00.000Z',
            form: { telFixed: '072-111-1111', mail: 'sato@example.com', keiken: KEIKEN_ARI, weekdays: ['月', '水'], skills: [{ field: 'Oubo_Skill_Syotoku_Zei__c', value: '5' }] },
            kanoubiDates: [{ kanoubiDate: '2026-11-03', timeSlots: [{ startTime: '13:00', endTime: '15:00' }] }]
        }
    },
    {
        jigyoKey: STUB_JIGYO_LIST[0].key,
        jujishaNo: '1000001',
        application: {
            applicationId: 'a00000000000002AAA',
            uketukeNo: 2,
            systemModstamp: '2026-10-02T02:30:00.000Z',
            form: { telMobile: '090-2222-2222', keiken: KEIKEN_ARI, weekdays: ['火', '木'], kibouNissu: '3', skills: [{ field: 'Oubo_Skill_Hojin_Zei__c', value: '4' }], sodanKamoku: '法人税' },
            kanoubiDates: [
                { kanoubiDate: '2026-11-03', timeSlots: [{ startTime: '09:00', endTime: '12:00' }] },
                { kanoubiDate: '2026-12-01', timeSlots: [{ startTime: '10:00', endTime: '11:00' }] }
            ]
        }
    },
    {
        jigyoKey: STUB_JIGYO_LIST[0].key,
        jujishaNo: '9000001',
        application: {
            applicationId: 'a00000000000003AAA',
            uketukeNo: 0, // 未採番（マイページからの応募）
            systemModstamp: '2026-10-03T00:15:00.000Z',
            form: { mail: 'ichiro@example.com', keiken: KEIKEN_NASHI, weekdays: [], biko: '午前のみ希望' },
            kanoubiDates: []
        }
    },
    {
        jigyoKey: STUB_JIGYO_LIST[1].key,
        jujishaNo: '1000001',
        application: {
            applicationId: 'a00000000000004AAA',
            uketukeNo: 1,
            systemModstamp: '2026-10-05T03:00:00.000Z',
            form: { telFixed: '06-4444-4444', keiken: KEIKEN_ARI, weekdays: ['土'], skills: [{ field: 'Oubo_Skill_Syohi_Zei__c', value: '3' }] },
            kanoubiDates: []
        }
    }
];
const isSameKey = (a, b) => a.jujiJigyoNo === b.jujiJigyoNo && a.jujiBasyoNo === b.jujiBasyoNo && a.jisiNendo === b.jisiNendo;
const STUB_JUJISHA = (jujishaNo) => ({
    jujishaType: 'MEMBER',
    name: 'テスト 太郎',
    furigana: 'テスト タロウ',
    shibuCode: '001',
    shibuName: '東支部',
    address: '東京都千代田区1-1-1',
    tel: '03-0000-0000',
    fax: '03-0000-0001',
    ...(STUB_JUJISHA_LIST[jujishaNo] || {}),
    jujishaNo
});
const STUB_INPUT_CONTROL = {
    requiredWeekday: false,
    requiredKanoubi: false,
    requiredKibouNissu: false,
    requiredSkill: false,
    optionalSkill: true,
    optionalSkillNote: true,
    optionalChosho: true,
    optionalSodanKamoku: true
};
const getJigyo = async (key) => {
    const found = STUB_JIGYO_LIST.find((j) => isSameKey(j.key, key));
    const basyo = STUB_JIGYO_LIST.find((j) => j.key.jujiBasyoNo === key.jujiBasyoNo);
    return {
        basyoName: basyo ? basyo.basyoName : '',
        jigyo: found
            ? { jigyoName: found.jigyoName, shibuCode: found.shibuCode, shibuName: found.shibuName, lastUketukeNo: found.lastUketukeNo, inputControl: STUB_INPUT_CONTROL }
            : null
    };
};
const getJujisha = async ({ jujishaNo }) => (jujishaNo === '9999999' ? null : STUB_JUJISHA(jujishaNo));
const loadApplication = async ({ applicationId, jujiJigyoNo, jujiBasyoNo, jisiNendo, jujishaNo }) => {
    // 応募情報検索からの戻り（応募ID指定）：その応募の事業キー・番号・応募を返す
    if (applicationId) {
        const app = STUB_APPLICATIONS.find((a) => a.application.applicationId === applicationId);
        if (!app) {
            throw { body: { message: '指定された応募情報は登録されていません。' } };
        }
        return { jigyoKey: { ...app.jigyoKey }, jujishaNo: app.jujishaNo, jujisha: STUB_JUJISHA(app.jujishaNo), application: app.application };
    }
    // 応募情報表示（従事事業キー＋番号指定）
    const key = { jujiJigyoNo, jujiBasyoNo, jisiNendo };
    if (jujishaNo === '9999999') {
        throw { body: { message: MSG.JUJISHA_NOT_FOUND } };
    }
    const app = STUB_APPLICATIONS.find((a) => isSameKey(a.jigyoKey, key) && a.jujishaNo === jujishaNo);
    return { jigyoKey: key, jujishaNo, jujisha: STUB_JUJISHA(jujishaNo), application: app ? app.application : null };
};
const checkJigyo = async () => {};
const saveApplication = async ({ requestJson }) => {
    const req = JSON.parse(requestJson);
    // 追加モードで登録済みの従事者を登録した場合（4.入力チェック No.18）
    if (!req.applicationId && STUB_APPLICATIONS.some((a) => isSameKey(a.jigyoKey, req.jigyoKey) && a.jujishaNo === req.jujishaNo)) {
        throw { body: { message: '指定された従事者の応募情報はすでに登録されています。応募情報表示ボタンで登録内容を表示してください。' } };
    }
    return { uketukeNo: 4 };
};
const deleteApplication = async () => {};
const deleteAllApplications = async () => {};
// ========== スタブ ここまで ==========

export default class JujJigyoOboTouroku extends NavigationMixin(LightningElement) {
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
    objectApiNames = [OBO_OBJECT, JIGYO_OBJECT, BASYO_OBJECT, SODANIN_OBJECT, OFFICE_OBJECT];
    @wire(getObjectInfos, { objectApiNames: '$objectApiNames' })
    objectInfos;

    // ========== No.1 画面初期化 ==========
    // 【要確認】遷移パラメータの受渡し方式（暫定：URL state）
    // ※ スタブ：STUB_PAGE_STATE に遷移元が設定されている場合はそれを使用する（ローカルプレビュー用。Apex デプロイ後は pageRef.state のみとする）
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (this._initialized || (!pageRef && !STUB_PAGE_STATE.c__from)) {
            return;
        }
        this._initialized = true;
        this.initialize(STUB_PAGE_STATE.c__from ? STUB_PAGE_STATE : pageRef.state || {});
    }

    async initialize(state) {
        // 追加モードとし、応募情報部を初期化する
        this.resetJujishaAndApplication();
        // 従事事業基本情報表示から遷移した場合：引き継いだ従事事業キーを設定し、No.18 従事事業情報入力を呼び出す
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
        // 従事事業メニューから遷移した場合：従事事業キー部は空白（入力制御は getter で行う）
    }

    // ========== No.2 従事事業No.／従事場所No.／実施年度のフォーカスアウト ==========
    handleJigyoKeyBlur(event) {
        const field = event.target.dataset.field; // jujiJigyoNo / jujiBasyoNo / jisiNendo
        this.jigyoKey = { ...this.jigyoKey, [field]: event.target.value };
        this.onJigyoKeyChanged();
    }

    // ========== No.3 従事事業検索ボタン押下（JUJ110） ==========
    // 検索条件は初期値なし。フォーカスアウトと同じ契機のため、メッセージは消去しない
    handleJigyoSearchClick() {
        this.isJigyoSearchOpen = true;
    }

    // 従事事業データが渡された場合：従事事業キー3項目を設定し、No.2 と同じ処理を行う
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

    // ========== No.4 従事場所検索ボタン押下（JUJ120） ==========
    handleBasyoSearchClick() {
        this.isBasyoSearchOpen = true;
    }

    // 従事場所データが渡された場合：従事場所No. を設定し、No.2 と同じ処理を行う
    handleBasyoSearchSelect(event) {
        this.isBasyoSearchOpen = false;
        const rec = event.detail.selectedRecord;
        this.jigyoKey = { ...this.jigyoKey, jujiBasyoNo: toText(rec.bashoNo) };
        this.onJigyoKeyChanged();
    }

    handleBasyoSearchClose() {
        this.isBasyoSearchOpen = false;
    }

    // No.2 の処理
    async onJigyoKeyChanged() {
        // 入力された項目の未入力エラーを消去する（頭部メッセージは次のボタン押下まで保持する）
        this.clearRequiredErrors(REQUIRED_JIGYO_KEY, this.jigyoKey);
        // 従事場所名の取得・No.18 従事事業情報入力
        await this.loadJigyo();
        // 3項目のいずれかが変わった場合、追加モードとし、応募情報部（受付番号・従事可能個別日を含む）を初期化する
        // 登録番号/相談員番号・従事者情報部は保持する。未登録の入力があっても確認ダイアログは表示しない
        if (!this.isSameJigyoKey(this.jigyoKey, this.prevJigyoKey)) {
            this.resetApplicationForm();
        }
        this.prevJigyoKey = { ...this.jigyoKey };
    }

    // ========== No.18 従事事業情報入力呼び出し（No.2 の従事場所名の取得を含む） ==========
    async loadJigyo() {
        const { jujiJigyoNo, jujiBasyoNo, jisiNendo } = this.jigyoKey;
        // 従事場所No. が変わっていない場合、従事場所名は再設定しない（表示のちらつき防止）
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
        // 従事場所No. 入力時は従事場所名、3項目すべて入力時は従事事業を取得する。いずれも該当しない場合は呼び出さない
        if (!jujiBasyoNo && !(jujiJigyoNo && jisiNendo)) {
            return;
        }
        try {
            // 戻り値：{ basyoName, jigyo: { jigyoName, shibuCode, shibuName, lastUketukeNo, inputControl } | null }
            const result = await getJigyo({ ...this.jigyoKey });
            if (isBasyoChanged) {
                this.basyoName = result.basyoName || '';
            }
            // 取得できなかった場合は空白とし、応募情報部を非活性とする（isApplicationDisabled）
            this.jigyo = result.jigyo || {};
            this.lastUketukeNo = result.jigyo ? result.jigyo.lastUketukeNo : null;
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== No.5 登録番号/相談員番号のフォーカスアウト ==========
    handleJujishaNoBlur(event) {
        this.jujishaNo = event.target.value;
        this.onJujishaNoChanged();
    }

    // ========== No.6 登録番号/相談員番号検索ボタン押下（JUJ140） ==========
    handleJujishaSearchClick() {
        this.isJujishaSearchOpen = true;
    }

    // 従事者データが渡された場合：番号（会員は登録番号、相談員は相談員番号）を設定し、No.5 と同じ処理を行う
    handleJujishaSearchSelect(event) {
        this.isJujishaSearchOpen = false;
        const rec = event.detail.selectedRecord;
        this.jujishaNo = toText(rec.startNo); // 登録番号があれば登録番号、なければ相談員番号
        this.onJujishaNoChanged();
    }

    handleJujishaSearchClose() {
        this.isJujishaSearchOpen = false;
    }

    // No.5 の処理
    async onJujishaNoChanged() {
        // 入力された場合は未入力エラーを消去する（頭部メッセージは次のボタン押下まで保持する）
        this.clearRequiredErrors(REQUIRED_JUJISHA, { jujishaNo: this.jujishaNo });
        // 変更されていない場合は何もしない
        if (this.jujishaNo === this.prevJujishaNo) {
            return;
        }
        this.prevJujishaNo = this.jujishaNo;
        // No.19 従事者情報部入力
        await this.loadJujisha();
        // 受付番号を空白、従事可能個別日を未指定とする（応募情報部のその他の入力内容は保持する）。追加モードとする
        // ※ 登録済みの応募がある従事者かどうかは登録時にサーバ側でチェックする（4.入力チェック No.18）
        this.kanoubiDates = [];
        this.uketukeNo = null;
        this.toAddMode();
    }

    // ========== No.19 従事者情報部入力呼び出し（取得できない場合はエラーとせず空白表示） ==========
    async loadJujisha() {
        this.jujisha = {};
        if (!this.jujishaNo) {
            return;
        }
        try {
            // 戻り値：{ jujishaType, jujishaNo, name, furigana, shibuCode, shibuName, address, tel, fax } | null
            const result = await getJujisha({ jujishaNo: this.jujishaNo });
            this.jujisha = result || {};
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== No.7 応募情報表示ボタン押下 ==========
    async handleShowApplicationClick() {
        this.clearMessages();
        // 4.入力チェック No.1〜6（No.17 従事者の存在はサーバ側でチェックする）
        // ※ エラーはまとめて表示するため、すべてのチェックを行ってから判定する
        const errors = [];
        const isValid = [this.validateJujishaNo(), this.validateJigyoKey(errors)].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        // 応募情報部に未登録の変更が存在する場合は確認する
        if (this.isDirty && !(await this.confirmDialog(MSG.CONFIRM_OVERWRITE, TITLE.SHOW_APPLICATION))) {
            return;
        }
        try {
            // 5.データ更新 (1)。戻り値：{ jujisha, application | null }
            const result = await loadApplication({ ...this.jigyoKey, jujishaNo: this.jujishaNo });
            // 従事者情報部・応募情報部を初期化し、取得した従事者を表示する
            this.resetApplicationForm();
            this.jujisha = result.jujisha || {};
            this.prevJujishaNo = this.jujishaNo;
            // 取得できた場合は No.20 応募情報読込（変更モード）、取得できなかった場合は追加モード
            if (result.application) {
                this.applyApplication(result.application);
            }
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== No.8 応募情報検索ボタン押下（JUJ082） ==========
    handleApplicationSearchClick() {
        this.clearMessages();
        this.isApplicationSearchOpen = true;
    }

    // 応募情報が渡されなかった場合（閉じる）：何もしない
    handleApplicationSearchClose() {
        this.isApplicationSearchOpen = false;
    }

    // 応募情報が渡された場合（応募行の選択）
    async handleApplicationSearchSelect(event) {
        this.isApplicationSearchOpen = false;
        const { applicationId } = event.detail;
        try {
            // 5.データ更新 (1)。戻り値：{ jigyoKey, jujishaNo, jujisha, application }
            const res = await loadApplication({ applicationId });
            // 従事事業メニューから遷移した場合：選択された応募の従事事業キーを設定し、No.18 従事事業情報入力を呼び出す
            if (this.fromScreen === FROM_MENU) {
                this.jigyoKey = { ...res.jigyoKey };
                await this.loadJigyo();
                this.prevJigyoKey = { ...this.jigyoKey };
            }
            // 選択された応募の従事者を設定し、No.20 応募情報読込を呼び出す（変更モード）
            this.jujishaNo = res.jujishaNo;
            this.prevJujishaNo = res.jujishaNo;
            this.jujisha = res.jujisha || {};
            this.applyApplication(res.application);
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== No.11 従事可能日入力ボタン押下 ==========
    async handleKanoubiInputClick() {
        this.clearMessages();
        // 4.入力チェック No.1〜7（エラーはまとめて表示する）
        const errors = [];
        const isValid = [this.validateJigyoKey(errors), this.validateJujisha(errors)].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        // 4.入力チェック No.14 実施日の有無・No.15 一括割当実行中（サーバ側でチェック）
        try {
            await checkJigyo({ ...this.jigyoKey, checkJisshibi: true });
        } catch (error) {
            this.showError(error);
            return;
        }
        // 従事可能日指定（JUJ081）を表示する（従事事業キー・番号・保持中の従事可能日を html で引き渡す）
        this.isKanoubiOpen = true;
    }

    // 「保存」で閉じられた場合：戻り値の従事可能日で保持内容を置き換える（DB は更新しない）
    handleKanoubiSave(event) {
        this.isKanoubiOpen = false;
        this.kanoubiDates = event.detail.kanoubiDates;
        this.isDirty = true;
    }

    // 「閉じる」で閉じられた場合：何もしない（JUJ081 の初期表示エラーで閉じた場合はメッセージを表示する）
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

    // No.9・No.10 全日程従事可能（ON：従事可能曜日を入力不可、OFF：入力可）
    handleAllDaysChange(event) {
        this.form = { ...this.form, allDays: event.target.checked };
        this.isDirty = true;
    }

    // 従事経験：ラジオボタンの選択値（有／無）を設定する
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
        const field = event.target.dataset.field; // 例：'Oubo_Skill_Syotoku_Zei__c'
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

    // ========== No.12 登録ボタン押下：5.データ更新 (2)(3) ==========
    async handleSaveClick() {
        this.clearMessages();
        // ① 入力チェック（画面）：4.入力チェック No.1〜13。エラーはまとめて表示する
        const errors = [];
        const isValid = [
            this.validateJigyoKey(errors),
            this.validateJujisha(errors),
            this.validateForSave(errors)
        ].every(Boolean);
        if (!this.showErrorMessages(errors, isValid)) {
            return;
        }
        // 4.入力チェック No.15 一括割当実行中（確認ダイアログの前にサーバ側でチェック。登録処理内でも再チェックする）
        try {
            await checkJigyo({ ...this.jigyoKey, checkJisshibi: false });
        } catch (error) {
            this.showError(error);
            return;
        }
        // 確認ダイアログ
        if (!(await this.confirmDialog(MSG.CONFIRM_SAVE, TITLE.SAVE))) {
            return;
        }
        this.isLoading = true;
        try {
            // ②〜④ 登録処理。戻り値：{ uketukeNo }（採番しなかった場合は null）
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
            // 受付番号を採番した場合は、最終受付番号に採番した受付番号を設定する
            if (result.uketukeNo != null) {
                this.lastUketukeNo = result.uketukeNo;
            }
            // 従事事業キー部は保持し、それ以外を初期化して追加モードとする
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.SAVED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== No.13 削除ボタン押下：5.データ更新 (4) ==========
    async handleDeleteClick() {
        this.clearMessages();
        // 確認ダイアログ
        if (!(await this.confirmDialog(MSG.CONFIRM_DELETE, TITLE.DELETE))) {
            return;
        }
        this.isLoading = true;
        try {
            // 削除処理（応募読込時のシステム更新日時を渡し、排他チェックを行う）
            await deleteApplication({ ...this.jigyoKey, jujishaNo: this.jujishaNo, systemModstamp: this.systemModstamp });
            // 登録番号/相談員番号・従事者情報部・応募情報部を初期化し、追加モードとする
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.DELETED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== No.14 全削除ボタン押下：5.データ更新 (5) ==========
    async handleDeleteAllClick() {
        this.clearMessages();
        // 4.入力チェック No.1〜5
        const errors = [];
        if (!this.showErrorMessages(errors, this.validateJigyoKey(errors))) {
            return;
        }
        // 確認ダイアログ（2回）
        const msg1 =
            `${MSG.CONFIRM_DELETE_ALL_1}\n従事事業名:${this.jigyo.jigyoName}\n支部名:${this.jigyo.shibuName}\n` +
            `従事場所名:${this.basyoName}\n実施年度:${this.jigyoKey.jisiNendo}`;
        if (!(await this.confirmDialog(msg1, TITLE.DELETE_ALL)) ||
            !(await this.confirmDialog(MSG.CONFIRM_DELETE_ALL_2, TITLE.DELETE_ALL))) {
            return;
        }
        this.isLoading = true;
        try {
            // 全削除処理
            await deleteAllApplications({ ...this.jigyoKey });
            // 登録番号/相談員番号・従事者情報部・応募情報部を初期化し、追加モードとする
            this.resetJujishaAndApplication();
            this.showSuccess(MSG.DELETED);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== No.15 クリア・No.16 戻る・No.17 メニューボタン押下 ==========
    async handleClearClick() {
        if (!(await this.confirmDiscard(TITLE.CLEAR))) {
            return;
        }
        // 従事事業メニューから遷移した場合：画面を初期表示の状態に戻す（従事事業キー部も初期化する）
        if (this.fromScreen === FROM_MENU) {
            this.jigyoKey = emptyJigyoKey();
            this.prevJigyoKey = emptyJigyoKey();
            this.basyoName = '';
            this.jigyo = {};
            this.lastUketukeNo = null;
        }
        // 従事事業基本情報表示から遷移した場合：従事事業キー部は保持し、それ以外を初期表示の状態に戻す
        this.resetJujishaAndApplication();
        this.clearMessages();
    }

    async handleBackClick() {
        if (!(await this.confirmDiscard(TITLE.BACK))) {
            return;
        }
        // 遷移元の画面に戻る【要確認】遷移元への戻り方
        window.history.back();
    }

    async handleMenuClick() {
        if (!(await this.confirmDiscard(TITLE.MENU))) {
            return;
        }
        // JUJ010 従事事業メニューに遷移する【要確認】JUJ010 のページ API 名
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'JUJ010' }
        });
    }

    // 未登録の変更（応募情報部、従事可能日）が存在する場合のみ確認する
    async confirmDiscard(title) {
        return !this.isDirty || this.confirmDialog(MSG.CONFIRM_DISCARD, title);
    }

    // ========== No.20 応募情報読込呼び出し ==========
    // 応募情報部・従事可能日を表示し、排他チェック用にシステム更新日時を保持する。変更モードとする
    applyApplication(app) {
        this.applicationId = app.applicationId;
        this.systemModstamp = app.systemModstamp;
        this.uketukeNo = app.uketukeNo;
        this.form = { ...emptyForm(), ...app.form };
        this.kanoubiDates = app.kanoubiDates || [];
        this.isDirty = false;
    }

    // ========== 4.入力チェック（画面） ==========
    // ※ 単項目のエラー（未入力・形式）は各項目の下に表示し、それ以外は errors に追加して頭部に表示する。
    //   戻り値はチェック結果（true：エラーなし）。

    // No.1〜3 必須入力、No.4 実施年度 フォーマット・桁数（項目の下）、No.5 従事事業 存在（頭部）
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

    // No.4 実施年度：半角数字4桁（西暦）以外の場合はエラー（項目の下。入力欄がない場合は頭部）
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

    // No.6 登録番号/相談員番号 必須入力（項目の下）
    validateJujishaNo() {
        return this.reportRequired(REQUIRED_JUJISHA, { jujishaNo: this.jujishaNo });
    }

    // No.6 必須入力（項目の下）、No.7 従事者 存在（頭部）
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

    // No.8〜13 登録時のチェック
    validateForSave(errors) {
        const ctrl = this.inputControl;
        const f = this.form;
        const errorCount = errors.length;
        // No.8 従事可能曜日 必須選択
        if (ctrl.requiredWeekday && !f.allDays && f.weekdays.length === 0) {
            errors.push(MSG.WEEKDAY_REQUIRED);
        }
        // No.9 従事可能日 必須選択（時間帯が1件以上選択されていること）
        if (ctrl.requiredKanoubi && !this.kanoubiDates.some((k) => k.timeSlots && k.timeSlots.length > 0)) {
            errors.push(MSG.KANOUBI_REQUIRED);
        }
        // No.11 スキル 必須選択（値が空の科目は未選択とみなす）
        if (ctrl.requiredSkill && !f.skills.some((s) => s.value)) {
            errors.push(MSG.SKILL_REQUIRED);
        }
        // No.10 希望従事日数（required・min・max・step）、No.12 連絡先（Mail）（type=email）：各項目の下に表示する
        // ※ html 側の lightning-input に data-validate を設定する（入力不可の項目はチェックされない）
        // 【要確認】No.13 連絡先（固定電話・携帯電話・FAX）は現在チェックなし（type=tel は形式チェックを行わない）
        const inputs = [...this.template.querySelectorAll('[data-validate]')];
        const isInputValid = inputs.reduce((ok, el) => el.reportValidity() && ok, true);
        return isInputValid && errors.length === errorCount;
    }

    // 単項目の必須チェック：values のうち未入力の項目の下に「{項目名}は必須入力項目です。」を表示する（入力済みの項目はエラーを消去する）
    // html 側の lightning-input に data-required（グループ名）・data-field（values のキー）を設定する
    reportRequired(group, values) {
        const labels = this.labels;
        this.template.querySelectorAll(`[data-required="${group}"]`).forEach((el) => {
            const field = el.dataset.field;
            el.setCustomValidity(values[field] ? '' : MSG.REQUIRED(labels[field]));
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

    // ========== 初期化・モード ==========
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
    // 確認ダイアログ（タイトル＝押下したボタン名＋「確認」）
    confirmDialog(message, label) {
        return LightningConfirm.open({ message, label });
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

    // No.10 希望従事日数：未入力（必須の場合）・形式不正のメッセージ（html の message-when-* に設定する）
    get kibouNissuRequiredMessage() {
        return MSG.REQUIRED(this.labels.kibouNissu);
    }

    get kibouNissuFormatMessage() {
        return MSG.KIBOU_NISSU_FORMAT;
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

    // ========== Getter（3.表示ラベルの入力制御） ==========
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

    // No.39 削除ボタン：追加モードでは使用不可
    get isDeleteDisabled() {
        return !this.isChangeMode;
    }

    // No.1・6・9 従事事業キー：従事事業基本情報から遷移した場合は入力不可
    get isJigyoKeyReadonly() {
        return this.fromScreen === FROM_JIGYO_INFO;
    }

    // 応募情報部：従事事業を取得できていない場合はすべて入力不可
    get isApplicationDisabled() {
        return !this.hasJigyo;
    }

    // No.29 従事可能曜日：全日程従事可能が ON、または必須入力フラグ（従事可能日）＝必須の場合は入力不可
    // ※ 必須入力フラグ（従事可能曜日）と（従事可能日）が同時に必須になることはない（事業側でチェック済み）
    get isWeekdayDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredKanoubi || this.form.allDays;
    }

    get isWeekdayRequired() {
        return !!this.inputControl.requiredWeekday;
    }

    // No.28 全日程従事可能：必須入力フラグ（従事可能日）＝必須の場合は入力不可
    get isAllDaysDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredKanoubi;
    }

    // No.31 従事可能日入力ボタン：必須入力フラグ（従事可能曜日）＝必須の場合は使用不可
    get isKanoubiButtonDisabled() {
        return this.isApplicationDisabled || !!this.inputControl.requiredWeekday;
    }

    // No.32 希望従事日数：必須入力フラグ（希望従事日数）＝必須の場合は必須
    get isKibouNissuRequired() {
        return !!this.inputControl.requiredKibouNissu;
    }

    // No.34 スキル：必須入力フラグ＝必須 → 必須、任意入力フラグ＝許可 → 入力可、それ以外 → 入力不可
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

    // No.35〜37 スキル特記事項・主な著書、論文・相談科目：任意入力フラグ＝許可 → 入力可、禁止 → 入力不可
    get isSkillNoteDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalSkillNote;
    }

    get isChoshoDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalChosho;
    }

    get isSodanKamokuDisabled() {
        return this.isApplicationDisabled || !this.inputControl.optionalSodanKamoku;
    }

    // No.33 従事経験：ラジオボタンの値・選択状態
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

    // No.30 従事可能個別日：1件以上なら「指定済」、0件なら「未指定」
    get kanoubiStatusLabel() {
        return this.kanoubiDates.length > 0 ? '指定済' : '未指定';
    }
}
