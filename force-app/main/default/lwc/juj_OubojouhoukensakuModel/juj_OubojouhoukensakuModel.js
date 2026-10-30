/**
 * JUJ082 応募情報検索（JUJ080 の子コンポーネントとしてモーダル表示する）
 *
 * 呼出し元（JUJ080）：
 *   <c-juj_-oubojouhoukensaku-model jigyo-key={jigyoKey} jigyo={jigyo} basyo-name={basyoName} key-readonly={isJigyoKeyReadonly}
 *             onselect={...} onclose={...}></c-juj_-oubojouhoukensaku-model>
 * イベント：
 *   select … 応募行の「選択」押下時。detail = { applicationId }
 *   close  … 閉じるボタン押下時
 */
import { LightningElement, api, wire } from 'lwc';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
// 汎用マスタの対象年度（取得できない場合は ''）
import getHanyouMasterTaisyoNendo from '@salesforce/apex/Juj_CommonController.getHanyouMasterTaisyoNendo';

import search from '@salesforce/apex/Juj_OubojouhoukensakuModelController.search';
import getJigyo from '@salesforce/apex/Juj_OubojouhoukensakuModelController.getJigyo';
import getName from '@salesforce/apex/Juj_OubojouhoukensakuModelController.getName';

// メッセージ【要確認 QA-20】
const MSG = {
    RANGE: (label) => `${label}(From)は${label}(To)以下の値を入力してください。`,
    NENDO_FORMAT: '実施年度は4桁の半角数字（西暦）で入力してください。',
    UNEXPECTED: '予期しないエラーが発生しました。'
};

// 実施年度：半角数字4桁（西暦）
const NENDO_PATTERN = /^[0-9]{4}$/;

// 項目ラベルの取得元オブジェクト
const OBO_OBJECT = 'Juji_Jigyo_Oubo__c'; // 従事事業応募
const JIGYO_OBJECT = 'Juji_Jigyo__c'; // 従事事業
const BASYO_OBJECT = 'Juji_Basyo_Master__c'; // 従事場所マスタ
const MEMBER_OBJECT = 'Contact'; // 会員（取引先責任者）
const SODANIN_OBJECT = 'Soudanin_Master__c'; // 相談員マスタ
const OFFICE_OBJECT = 'Account'; // 事務所・法人

// 画面項目 → [オブジェクト, 項目名, 既定ラベル]（項目ラベルを取得できない場合は既定ラベル。検索条件・検索結果の列名で共通）
const LABEL_FIELDS = {
    jujiJigyoNo: [JIGYO_OBJECT, 'Juji_Juji_Jigyo_No__c', '従事事業No.'],
    jigyoName: [JIGYO_OBJECT, 'Juji_Juji_Jigyo_Name__c', '従事事業名'],
    jisiNendo: [JIGYO_OBJECT, 'Juji_Jisi_Nendo__c', '実施年度'],
    jujiBasyoNo: [BASYO_OBJECT, 'JujM_Juji_Basyo_No__c', '従事場所No.'],
    basyoName: [BASYO_OBJECT, 'JujM_Juji_Basyo_Name__c', '従事場所名'],
    shibuCode: [OFFICE_OBJECT, 'Jims_Sibu_Code__c', '支部コード'],
    uketukeNo: [OBO_OBJECT, 'Oubo_Uketuke_No__c', '受付番号'],
    torokuNo: [MEMBER_OBJECT, 'Kaii_Toroku_No__c', '登録番号'],
    sodaninNo: [SODANIN_OBJECT, 'SouM_Sodanin_No__c', '相談員番号'],
    name: [SODANIN_OBJECT, 'SouM_Sodanin_Name__c', '氏名']
};

// 相関（区間）チェックの From／To（画面項目名, 数値比較か）
const RANGES = [
    ['uketukeNo', true],
    ['torokuNo', false],
    ['shibuCode', false],
    ['sodaninNo', false]
];

// 番号 → 名称取得の種別（Apex getName の nameType）
const NAME_TYPES = {
    torokuNo: 'TOROKU', // 登録番号 → 会員氏名
    shibuCode: 'SHIBU', // 支部コード → 支部名
    sodaninNo: 'SODANIN' // 相談員番号 → 相談員氏名
};

// 検索結果の列（列名は labels から設定する。登録日時は固定）
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
    { label: labels.jujiBasyoNo, fieldName: 'jujiBasyoNo', sortable: true },
    { label: labels.basyoName, fieldName: 'basyoName', sortable: true },
    { label: labels.jisiNendo, fieldName: 'jisiNendo', sortable: true },
    { label: '登録日時', fieldName: 'createdDate', sortable: true }
];

// 共通の検索子画面の重なり順（本画面がモーダルのため 2）
const SUB_SCREEN_LEVEL = 2;
const SUB_JIGYO = 'JUJ110'; // 従事事業検索
const SUB_BASYO = 'JUJ120'; // 従事場所検索
const SUB_SHIBU = 'JUJ130'; // 支部検索
const SUB_JUJISHA = 'JUJ140'; // 従事対象者検索
const SUB_SODANIN = 'JUJ150'; // 相談員情報検索

// 検索子画面の戻り値は数値の場合もあるため文字列にする
const toText = (value) => (value == null ? '' : String(value));

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

export default class JujOubojouhoukensakuModel extends LightningElement {
    // JUJ080 からの引継ぎ
    @api jigyoKey; // { jujiJigyoNo, jujiBasyoNo, jisiNendo }
    @api jigyo; // 取得済みの事業 { jigyoName, shibuCode, shibuName }
    @api basyoName;
    @api keyReadonly = false; // true＝従事事業基本情報から遷移（従事事業キーは入力不可）

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

    headerMessages = []; // 画面頭部のエラーメッセージ
    isLoading = false;

    // 共通の検索子画面
    subScreenId = null; // 表示中の子画面（null＝非表示）
    subScreenField = null; // 戻り値を設定する検索条件の項目（例：torokuNoFrom）
    subScreenLevel = SUB_SCREEN_LEVEL;

    // 項目ラベルの取得
    objectApiNames = [OBO_OBJECT, JIGYO_OBJECT, BASYO_OBJECT, MEMBER_OBJECT, SODANIN_OBJECT, OFFICE_OBJECT];
    objectInfos;
    // 検索結果の列（項目ラベルの取得後に列名を設定し直す）
    // ※ 再描画のたびに作り直すと列幅・折り返しの設定がリセットされるため、取得時のみ設定する
    columns = buildColumns(this.labels);

    @wire(getObjectInfos, { objectApiNames: '$objectApiNames' })
    wiredObjectInfos(result) {
        this.objectInfos = result;
        this.columns = buildColumns(this.labels);
    }

    // ========== 画面初期化 ==========
    connectedCallback() {
        this.lockPageScroll();
        this.initKey();
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

    // 従事事業キー部を初期表示の状態にする（初期表示・クリアで使用）
    initKey() {
        this.key = { ...emptyKey(), ...(this.jigyoKey || {}) };
        this.prevKey = { ...this.key };
        this.currentJigyo = { ...(this.jigyo || {}) };
        this.currentBasyoName = this.basyoName || '';
        // 従事事業メニューから遷移し、実施年度が空白の場合は汎用マスタの対象年度を設定して事業を取得する
        if (!this.keyReadonly && !this.key.jisiNendo) {
            this.setDefaultNendo();
        }
    }

    async setDefaultNendo() {
        try {
            const nendo = await getHanyouMasterTaisyoNendo();
            if (nendo) {
                this.key = { ...this.key, jisiNendo: nendo };
                await this.onKeyChanged();
            }
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 従事事業キーのフォーカスアウト ==========
    handleKeyBlur(event) {
        const field = event.target.dataset.field;
        this.key = { ...this.key, [field]: event.target.value };
        // 実施年度の形式エラーは次の検索ボタン押下まで表示しない
        if (field === 'jisiNendo') {
            this.clearNendoError();
        }
        this.onKeyChanged();
    }

    async onKeyChanged() {
        await this.loadJigyo();
        // キーが変わった場合は検索結果を消去する
        if (!this.isSameKey(this.key, this.prevKey)) {
            this.searchData = [];
        }
        this.prevKey = { ...this.key };
    }

    // 従事場所名・従事事業の取得（JUJ080 と同じ。最終受付番号・入力制御は扱わない）
    async loadJigyo() {
        const { jujiJigyoNo, jujiBasyoNo, jisiNendo } = this.key;
        // 表示のちらつき防止のため、変わっていない場合は取得結果が返るまで現在の表示を保持する
        const isBasyoChanged = jujiBasyoNo !== this.prevKey.jujiBasyoNo;
        if (isBasyoChanged) {
            this.currentBasyoName = '';
        }
        if (!this.isSameKey(this.key, this.prevKey)) {
            this.currentJigyo = {};
        }
        if (!jujiBasyoNo && !(jujiJigyoNo && jisiNendo)) {
            return;
        }
        try {
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

    // ========== 登録番号／支部コード／相談員番号のフォーカスアウト ==========
    // 横に名称を表示する（未入力・取得できない場合は空白）
    async handleNoBlur(event) {
        const field = event.target.dataset.field;
        const code = event.target.value;
        const nameType = NAME_TYPES[field.replace(/(From|To)$/, '')];
        try {
            const name = code ? await getName({ nameType, code }) : null;
            this.names = { ...this.names, [field]: name || '' };
        } catch (error) {
            this.showError(error);
        }
    }

    // ========== 検索 ==========
    async handleSearchAction() {
        this.headerMessages = [];
        // すべてチェックしてからまとめて表示する
        const isRangeValid = this.validateRanges();
        const isNendoValid = this.validateNendoFormat();
        if (!isRangeValid || !isNendoValid) {
            return;
        }
        this.isLoading = true;
        try {
            // 従事事業キーが未入力、または従事事業が存在しない場合は 0件
            const result = await search({ conditionJson: JSON.stringify(this.buildCondition()) });
            // 従事事業No.・従事事業名・従事場所No.・従事場所名・実施年度は画面の値を設定する
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

    // 相関（区間）チェック：From ＞ To の場合はエラー（頭部）
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
        }).map(([key]) => MSG.RANGE(labels[key]));
        this.headerMessages = errors;
        return errors.length === 0;
    }

    // 実施年度：入力可の場合のみ、半角数字4桁以外はエラー（項目の下）。未入力はエラーとしない（0件）
    validateNendoFormat() {
        const nendo = this.key.jisiNendo;
        const isValid = this.keyReadonly || !nendo || NENDO_PATTERN.test(nendo);
        const el = this.nendoInput;
        if (el) {
            el.setCustomValidity(isValid ? '' : MSG.NENDO_FORMAT);
            el.reportValidity();
        }
        return isValid;
    }

    clearNendoError() {
        const el = this.nendoInput;
        if (el) {
            el.setCustomValidity('');
            el.reportValidity();
        }
    }

    get nendoInput() {
        return this.template.querySelector('lightning-input[data-field="jisiNendo"]');
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

    // ========== 検索結果の並べ替え（画面内。再検索は行わない） ==========
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

    // ========== 選択（応募IDを JUJ080 に返す） ==========
    handleRowAction(event) {
        if (event.detail.action.name === 'select_row') {
            const applicationId = event.detail.row.applicationId;
            this.dispatchEvent(new CustomEvent('select', { detail: { applicationId } }));
        }
    }

    // ========== 共通の検索子画面（JUJ110・120・130・140・150） ==========
    // 【要確認】共通担当の子画面の組込み方
    // フォーカスアウトと同じ扱いのため、メッセージは消去しない
    handleSubSearchClick(event) {
        this.subScreenId = event.target.dataset.screen;
        this.subScreenField = event.target.dataset.field || null;
    }

    // JUJ110・120：キーを設定して事業を取得する（戻り値の名称は使用しない）
    // JUJ130・140・150：番号と戻り値の名称を設定する
    handleSubScreenSelect(event) {
        const rec = event.detail.selectedRecord;
        const screenId = this.subScreenId;
        const field = this.subScreenField;
        this.closeSubScreen();
        if (screenId === SUB_JIGYO) {
            this.key = { jujiJigyoNo: toText(rec.jigyoNo), jujiBasyoNo: toText(rec.bashoNo), jisiNendo: toText(rec.nendo) };
            this.onKeyChanged();
        } else if (screenId === SUB_BASYO) {
            this.key = { ...this.key, jujiBasyoNo: toText(rec.bashoNo) };
            this.onKeyChanged();
        } else if (screenId === SUB_SHIBU) {
            this.setConditionNo(field, rec.shibuCode, rec.shibuName);
        } else if (screenId === SUB_JUJISHA) {
            // ※ 登録番号の検索ボタンは現在なし（html でコメントアウト）
            // 相談員（登録番号なし）が選択された場合は設定しない
            if (rec.torokuNo) {
                this.setConditionNo(field, rec.torokuNo, rec.name);
            }
        } else if (screenId === SUB_SODANIN) {
            this.setConditionNo(field, rec.sodanNo, rec.sodanName);
        }
    }

    handleSubScreenClose() {
        this.closeSubScreen();
    }

    closeSubScreen() {
        this.subScreenId = null;
        this.subScreenField = null;
    }

    // 検索条件の番号と、番号の横に表示する名称を設定する
    setConditionNo(field, no, name) {
        this.condition = { ...this.condition, [field]: toText(no) };
        this.names = { ...this.names, [field]: toText(name) };
    }

    // ========== クリア ==========
    // 画面を開いた時の状態に戻す（従事事業キー部は JUJ080 から引き継いだ値に戻す）
    handleClearSearch() {
        this.initKey();
        this.condition = emptyCondition();
        this.names = emptyNames();
        this.searchData = [];
        this.sortBy = undefined;
        this.sortDirection = undefined;
        this.headerMessages = [];
        this.clearNendoError();
    }

    pageOverflow = ''; // 表示前のページのスクロール設定（閉じたときに戻す）

    // ========== 閉じる（JUJ080 に返さない） ==========
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

    getFieldInfos(objectApiName) {
        const results = this.objectInfos?.data?.results || [];
        const info = results.find((r) => r.result && r.result.apiName === objectApiName);
        return info ? info.result.fields : {};
    }

    // ========== Getter ==========
    // 従事事業基本情報から遷移した場合は従事事業キーが入力不可、検索ボタンが非活性
    get isInputDisabled() {
        return this.keyReadonly;
    }

    get hasHeaderMessages() {
        return this.headerMessages.length > 0;
    }

    // 共通の検索子画面の表示有無
    get isJigyoSearchOpen() {
        return this.subScreenId === SUB_JIGYO;
    }

    get isBasyoSearchOpen() {
        return this.subScreenId === SUB_BASYO;
    }

    get isShibuSearchOpen() {
        return this.subScreenId === SUB_SHIBU;
    }

    get isJujishaSearchOpen() {
        return this.subScreenId === SUB_JUJISHA;
    }

    get isSodaninSearchOpen() {
        return this.subScreenId === SUB_SODANIN;
    }

    // 画面項目のラベル（項目ラベル。取得できない場合は既定ラベル）
    get labels() {
        const labels = {};
        Object.entries(LABEL_FIELDS).forEach(([key, [objectApiName, field, defaultLabel]]) => {
            const fieldInfo = this.getFieldInfos(objectApiName)[field];
            labels[key] = fieldInfo ? fieldInfo.label : defaultLabel;
        });
        return labels;
    }
}
