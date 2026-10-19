/**
 * JUJ082 応募情報検索（JUJ080 の子コンポーネントとしてモーダル表示する）
 * 設計書：JUJ082 応募情報検索 検索処理 v7
 * コメント中の番号は検索処理の章番号に対応する。【要確認】は QA・メタデータの確定後に修正する。
 *
 * 呼出し元（JUJ080）：
 *   <c-juj082 jigyo-key={jigyoKey} jigyo={jigyo} basyo-name={basyoName} key-readonly={isJigyoKeyReadonly}
 *             onselect={...} onclose={...}></c-juj082>
 * イベント：
 *   select … 応募行の「選択」押下時。detail = { applicationId }
 *   close  … 閉じるボタン押下時
 */
import { LightningElement, api, wire } from 'lwc';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';

// ========== Apex（未デプロイのため一時的にコメントアウト。デプロイ後は import を戻し、下のスタブを削除する）==========
// import search from '@salesforce/apex/JUJ082Controller.search';
// import getJigyo from '@salesforce/apex/JUJ082Controller.getJigyo';
// import getName from '@salesforce/apex/JUJ082Controller.getName';
// import getDefaultNendo from '@salesforce/apex/JUJ082Controller.getDefaultNendo';

// 【要確認 QA-20】メッセージ文言・ID
const MSG = {
    RANGE: '範囲指定が正しくありません。', // SYSTEM-5104
    UNEXPECTED: '予期しないエラーが発生しました。'
};

// 項目ラベルの取得元オブジェクト（【要確認】API 名確定後に置換）
const OBO_OBJECT = '従事事業応募__c'; // 従事事業応募
const JIGYO_OBJECT = '従事事業__c'; // 従事事業
const MEMBER_OBJECT = 'Contact'; // 会員（取引先責任者）
const SODANIN_OBJECT = '相談員__c'; // 相談員マスタ
const OFFICE_OBJECT = 'Account'; // 事務所・法人

// 画面項目 → [オブジェクト, 項目名, 既定ラベル]。ラベルはメタデータから取得し、取得できない場合は既定ラベルを表示する
// （検索条件・検索結果の列名で共通。列名は検索した項目のオブジェクトから取得する）
const LABEL_FIELDS = {
    jujiJigyoNo: [JIGYO_OBJECT, '従事事業No__c', '従事事業No.'],
    jigyoName: [JIGYO_OBJECT, '従事事業名__c', '従事事業名'],
    jisiNendo: [JIGYO_OBJECT, '実施年度__c', '実施年度'],
    shibuCode: [OFFICE_OBJECT, '支部コード__c', '支部コード'],
    uketukeNo: [OBO_OBJECT, '受付番号__c', '受付番号'],
    torokuNo: [MEMBER_OBJECT, '登録番号__c', '登録番号'],
    sodaninNo: [SODANIN_OBJECT, '相談員番号__c', '相談員番号'],
    name: [SODANIN_OBJECT, '氏名__c', '氏名']
};

// From／To の組（画面項目名, 数値比較か）。エラーメッセージには画面項目のラベルを使用する
const RANGES = [
    ['uketukeNo', true],
    ['torokuNo', false],
    ['shibuCode', false],
    ['sodaninNo', false]
];

// 番号 → 名称取得の種別（Apex の getName の nameType）
const NAME_TYPES = {
    torokuNo: 'TOROKU', // 登録番号 → 会員氏名
    shibuCode: 'SHIBU', // 支部コード → 支部名
    sodaninNo: 'SODANIN' // 相談員番号 → 相談員氏名
};

// 検索結果の列（【要確認】検索結果項目一覧の提供後に見直す。暫定：現行 WLP008 と同じ列）
// 列名は labels を設定する。従事場所No.・従事場所名・登録日時は固定
const buildColumns = (labels) => [
    {
        type: 'button',
        initialWidth: 70,
        typeAttributes: { label: '選択', name: 'select_row', title: '選択', variant: 'base' }
    },
    { label: labels.uketukeNo, fieldName: 'uketukeNo', type: 'number', sortable: true, cellAttributes: { alignment: 'left' } },
    { label: labels.torokuNo, fieldName: 'torokuNo', sortable: true },
    { label: labels.sodaninNo, fieldName: 'sodaninNo', sortable: true },
    { label: labels.name, fieldName: 'name', sortable: true },
    { label: labels.jujiJigyoNo, fieldName: 'jujiJigyoNo', sortable: true },
    { label: labels.jigyoName, fieldName: 'jigyoName', sortable: true },
    { label: '従事場所No.', fieldName: 'jujiBasyoNo', sortable: true },
    { label: '従事場所名', fieldName: 'basyoName', sortable: true },
    { label: labels.jisiNendo, fieldName: 'jisiNendo', sortable: true },
    { label: '登録日時', fieldName: 'createdDate', sortable: true }
];

const emptyKey = () => ({ jujiJigyoNo: '', jujiBasyoNo: '', jisiNendo: '' });

const emptyCondition = () => ({
    uketukeNoFrom: '',
    uketukeNoTo: '',
    torokuNoFrom: '',
    torokuNoTo: '',
    shibuCodeFrom: '',
    shibuCodeTo: '',
    sodaninNoFrom: '',
    sodaninNoTo: '',
    name: ''
});

// 番号の横に表示する名称
const emptyNames = () => ({
    torokuNoFrom: '',
    torokuNoTo: '',
    shibuCodeFrom: '',
    shibuCodeTo: '',
    sodaninNoFrom: '',
    sodaninNoTo: ''
});

// ========== スタブ（Apex デプロイ後に削除）==========
// テスト用：番号に 9999999 → 名称なし
const search = async () => [
    { applicationId: 'a00000000000001AAA', uketukeNo: 1, torokuNo: '1000002', sodaninNo: null, name: '佐藤 花子', createdDate: '2026/10/01 10:00:00' },
    { applicationId: 'a00000000000002AAA', uketukeNo: 2, torokuNo: '1000001', sodaninNo: null, name: '山田 太郎', createdDate: '2026/10/02 11:30:00' },
    { applicationId: 'a00000000000003AAA', uketukeNo: 0, torokuNo: null, sodaninNo: '9000001', name: '山田 一郎', createdDate: '2026/10/03 09:15:00' }
];
const getJigyo = async ({ jujiJigyoNo, jujiBasyoNo, jisiNendo }) => ({
    basyoName: jujiBasyoNo ? `テスト場所${jujiBasyoNo}` : '',
    jigyo:
        jujiJigyoNo && jujiBasyoNo && jisiNendo && jujiJigyoNo !== '9999999'
            ? { jigyoName: 'テスト事業', shibuCode: '001', shibuName: 'テスト支部' }
            : null
});
const getName = async ({ code }) => (code && code !== '9999999' ? `テスト名称${code}` : null);
const getDefaultNendo = async () => '2026';
// ========== スタブ ここまで ==========

export default class Juj082 extends LightningElement {
    // 呼出し元（JUJ080）からの引継ぎ
    @api jigyoKey; // { jujiJigyoNo, jujiBasyoNo, jisiNendo }
    @api jigyo; // 呼出し元で取得済みの事業 { jigyoName, shibuCode, shibuName }
    @api basyoName; // 呼出し元で取得済みの従事場所名
    @api keyReadonly = false; // true：従事事業基本情報から遷移（従事事業キーは入力不可）

    // 従事事業キー部（画面の値）
    key = emptyKey();
    prevKey = emptyKey();
    currentJigyo = {}; // { jigyoName, shibuCode, shibuName }。{}＝未取得
    currentBasyoName = '';

    // 検索条件・結果
    condition = emptyCondition();
    names = emptyNames();
    searchData = [];
    sortBy;
    sortDirection;

    headerMessages = []; // 画面頭部に表示するエラーメッセージ
    isLoading = false;

    // 項目ラベル取得用のオブジェクト情報
    objectApiNames = [OBO_OBJECT, JIGYO_OBJECT, MEMBER_OBJECT, SODANIN_OBJECT, OFFICE_OBJECT];
    objectInfos;
    // 検索結果の列（初期は既定ラベル。オブジェクト情報の取得後に列名を設定し直す）
    // ※ 再描画のたびに列定義を作り直すと、列幅・折り返し等の設定がリセットされるため、取得時のみ設定する
    columns = buildColumns(this.labels);

    @wire(getObjectInfos, { objectApiNames: '$objectApiNames' })
    wiredObjectInfos(result) {
        this.objectInfos = result;
        this.columns = buildColumns(this.labels);
    }

    // ========== 初期表示 ==========
    connectedCallback() {
        this.initKey();
    }

    // 従事事業キー部を初期表示の状態にする（初期表示・クリアで使用）
    initKey() {
        // 呼出し元の従事事業キー・取得済みの事業情報を表示する
        this.key = { ...emptyKey(), ...(this.jigyoKey || {}) };
        this.prevKey = { ...this.key };
        this.currentJigyo = { ...(this.jigyo || {}) };
        this.currentBasyoName = this.basyoName || '';
        // 実施年度が空白の場合、汎用マスタの対象年度を初期値とする（従事事業メニューから遷移した場合のみ）
        if (!this.keyReadonly && !this.key.jisiNendo) {
            this.setDefaultNendo();
        }
    }

    async setDefaultNendo() {
        try {
            const nendo = await getDefaultNendo();
            if (nendo) {
                this.key = { ...this.key, jisiNendo: nendo };
                await this.onKeyChanged();
            }
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 従事事業キー変更時（フォーカスアウト） ==========
    handleKeyBlur(event) {
        const field = event.target.dataset.field; // jujiJigyoNo / jujiBasyoNo / jisiNendo
        this.key = { ...this.key, [field]: event.target.value };
        this.onKeyChanged();
    }

    async onKeyChanged() {
        await this.loadJigyo();
        // 従事事業キーが変わった場合、検索結果は前の事業のものとなるため消去する
        if (!this.isSameKey(this.key, this.prevKey)) {
            this.searchData = [];
        }
        this.prevKey = { ...this.key };
    }

    // 事業の取得（JUJ080 2.(1) と同じ）
    async loadJigyo() {
        const { jujiJigyoNo, jujiBasyoNo, jisiNendo } = this.key;
        // 従事場所No が変わっていない場合、従事場所名は再設定しない（表示のちらつき防止）
        const isBasyoChanged = jujiBasyoNo !== this.prevKey.jujiBasyoNo;
        if (isBasyoChanged) {
            this.currentBasyoName = '';
        }
        // 従事事業キーが変わっていない場合は、取得結果が返るまで現在の表示を保持する（表示のちらつき防止）
        if (!this.isSameKey(this.key, this.prevKey)) {
            this.currentJigyo = {};
        }
        if (!jujiBasyoNo && !(jujiJigyoNo && jisiNendo)) {
            return;
        }
        try {
            // 戻り値：{ basyoName, jigyo: { jigyoName, shibuCode, shibuName } | null }
            const result = await getJigyo({ ...this.key });
            if (isBasyoChanged) {
                this.currentBasyoName = result.basyoName || '';
            }
            this.currentJigyo = result.jigyo || {};
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 検索条件の入力 ==========
    handleConditionChange(event) {
        const field = event.target.dataset.field;
        this.condition = { ...this.condition, [field]: event.detail.value };
    }

    // 登録番号・支部コード・相談員番号のフォーカスアウト：横に名称を表示する（取得できない場合は空白）
    async handleNoBlur(event) {
        const field = event.target.dataset.field; // 例：torokuNoFrom
        const code = event.target.value;
        const nameType = NAME_TYPES[field.replace(/(From|To)$/, '')];
        try {
            const name = code ? await getName({ nameType, code }) : null;
            this.names = { ...this.names, [field]: name || '' };
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 1. 検索ボタン押下時 ==========
    async handleSearchAction() {
        this.headerMessages = [];
        // (1) 入力チェック：From ＞ To の場合はエラー（複数項目の関連チェックのため頭部に表示）
        if (!this.validateRanges()) {
            return;
        }
        this.isLoading = true;
        try {
            // (2)〜(7) 検索（従事事業が取得できない場合はサーバ側で 0件を返す）
            const result = await search({ conditionJson: JSON.stringify(this.buildCondition()) });
            // (5) 従事事業No・従事事業名・従事場所No・従事場所名・実施年度は画面の値を設定する
            this.searchData = result.map((row) => ({
                ...row,
                jujiJigyoNo: this.key.jujiJigyoNo,
                jigyoName: this.currentJigyo.jigyoName,
                jujiBasyoNo: this.key.jujiBasyoNo,
                basyoName: this.currentBasyoName,
                jisiNendo: this.key.jisiNendo
            }));
            this.sortBy = undefined;
            this.sortDirection = undefined;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // (1) From／To の範囲チェック
    validateRanges() {
        const c = this.condition;
        const labels = this.labels;
        const errors = RANGES.filter(([key, isNumber]) => {
            const from = c[key + 'From'];
            const to = c[key + 'To'];
            if (!from || !to) {
                return false;
            }
            return isNumber ? Number(from) > Number(to) : from > to;
        }).map(([key]) => `${labels[key]}：${MSG.RANGE}`);
        this.headerMessages = errors;
        return errors.length === 0;
    }

    // サーバへ渡す検索条件
    buildCondition() {
        const c = this.condition;
        return {
            ...this.key,
            uketukeNoFrom: c.uketukeNoFrom === '' ? null : Number(c.uketukeNoFrom),
            uketukeNoTo: c.uketukeNoTo === '' ? null : Number(c.uketukeNoTo),
            torokuNoFrom: c.torokuNoFrom,
            torokuNoTo: c.torokuNoTo,
            shibuCodeFrom: c.shibuCodeFrom,
            shibuCodeTo: c.shibuCodeTo,
            sodaninNoFrom: c.sodaninNoFrom,
            sodaninNoTo: c.sodaninNoTo,
            name: c.name
        };
    }

    // ========== 検索結果の並替え（画面内で並び替える） ==========
    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        const sign = sortDirection === 'asc' ? 1 : -1;
        // 空白は昇順・降順とも末尾とする
        const isBlank = (v) => v === null || v === undefined || v === '';
        this.searchData = [...this.searchData].sort((a, b) => {
            const x = a[fieldName];
            const y = b[fieldName];
            if (isBlank(x) || isBlank(y)) {
                return isBlank(x) - isBlank(y);
            }
            return x > y ? sign : x < y ? -sign : 0;
        });
        this.sortBy = fieldName;
        this.sortDirection = sortDirection;
    }

    // ========== 行選択：選択した応募の ID を呼出し元に返す ==========
    handleRowAction(event) {
        if (event.detail.action.name === 'select_row') {
            const applicationId = event.detail.row.applicationId;
            this.dispatchEvent(new CustomEvent('select', { detail: { applicationId } }));
        }
    }

    // ========== 検索ボタン（共通子画面） ==========
    // 【要確認】JUJ110・120・130・140・150（共通担当）の組込み方。接続までは仮表示とする
    handleSubSearchClick(event) {
        const screenId = event.target.dataset.screen;
        this.headerMessages = [`${screenId} は未接続です。`]; // 開発中の仮表示
    }

    // ========== クリア・閉じる ==========
    // 画面を初期表示の状態に戻す
    // ※ 従事事業キー部は呼出し元から引き継いだ値に戻す（従事事業基本情報から遷移した場合は入力不可のため変わらない。
    //   従事事業メニューから遷移した場合は入力した値を破棄し、実施年度が空白なら汎用マスタの対象年度を設定する）
    handleClearSearch() {
        this.initKey();
        this.condition = emptyCondition();
        this.names = emptyNames();
        this.searchData = [];
        this.sortBy = undefined;
        this.sortDirection = undefined;
        this.headerMessages = [];
    }

    closeSearchModal() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ========== 共通 ==========
    showError(error) {
        this.headerMessages = [error?.body?.message || MSG.UNEXPECTED];
    }

    isSameKey(a, b) {
        return a.jujiJigyoNo === b.jujiJigyoNo && a.jujiBasyoNo === b.jujiBasyoNo && a.jisiNendo === b.jisiNendo;
    }

    // 項目ラベル取得：指定オブジェクトの項目情報（未取得時は空オブジェクト）
    getFieldInfos(objectApiName) {
        const results = this.objectInfos?.data?.results || [];
        const info = results.find((r) => r.result && r.result.apiName === objectApiName);
        return info ? info.result.fields : {};
    }

    // ========== Getter ==========
    // 従事事業キー：従事事業基本情報から遷移した場合は入力不可、検索ボタン非表示
    get isInputDisabled() {
        return this.keyReadonly;
    }

    get isSearchButtonVisible() {
        return !this.keyReadonly;
    }

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
}
