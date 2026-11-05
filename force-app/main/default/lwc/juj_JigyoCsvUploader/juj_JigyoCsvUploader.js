/**
 * 従事事業CSV登録（ファイル一括登録）
 * ※ 1 ファイルに以下の部品をまとめている：メッセージ／コード変換表／ファイルレイアウト／CSV の読込／
 *   エラーの収集・出力／ファイル内チェック／事業単位の整理／整合性チェック／画面（コンポーネント）。後で差し替える部品は見出しで区切っている。
 * 処理の流れ（設計書「31」前提 4）：
 *   登録ボタン → ファイル単位のチェック（No.1～3、画面に表示）→ 確認ダイアログ
 *   → ファイルの読込（No.4・読込不可、画面に表示）→ ファイル内チェック（ログに出力）
 *   → ② 事業単位の整理 → ③④ 整合性チェック（ログに出力）→ 事業単位の登録（後続）
 * ※ 行単位のエラーは当面コンソールログに出力し、画面には SYSTEM-6105 のみ表示する【要確認 F-8】
 */
import { LightningElement, track } from 'lwc';
import getLoginUserInfo from '@salesforce/apex/Juj_JigyoCsvUploaderController.getLoginUserInfo';
import checkCategory2 from '@salesforce/apex/Juj_JigyoCsvUploaderController.checkCategory2';

// ============================================================
// メッセージ
// ============================================================
/**
 * 従事事業CSV登録 メッセージ
 * 現行のメッセージ ID・文言（設計書「30」）。xxxxx・yyyyy・zzzzz は置換文字、[ ] は文言の一部。
 * 【要確認 C-8】新システムでのメッセージの管理方法が決まったら、この部分だけを差し替える。
 */
const TEMPLATES = {
    'WLP029-0001': '対象ファイルをチェックしてください。',
    'WLP029-0002': '[xxxxx] ファイルを選択してください。',
    'WLP029-0003': '[従事事業No] と [従事場所No] と [実施年度] がファイル内で重複しています。',
    'WLP029-0004': '[従事事業No] と [従事場所No] と [実施年度] と [xxxxx] がファイル内で重複しています。',
    'WLP029-0005': '[従事事業No] と [従事場所No] と [実施年度] と [xxxxx] と [yyyyy] がファイル内で重複しています。',
    'WLP029-0006': '[従事事業No] と [従事場所No] と [実施年度] は既に登録されています。',
    'WLP029-0007': '[従事事業No] と [従事場所No] と [実施年度] と [xxxxx] は既に登録されています。',
    'WLP029-0008': '[従事事業No] と [従事場所No] と [実施年度] と [xxxxx] と [yyyyy] は既に登録されています。',
    'WLP029-0009': '[xxxxx] と [yyyyy] が一致しません。',
    'WLP029-0010': '[支部コード] が「000」の場合、[支部ユーザ操作] は「2（不可）」にしてください。',
    'WLP029-0012': '[xxxxx] と [yyyyy] はいずれかを「zzzzz」にしてください。',
    'WLP029-0013': '[xxxxx] は従事場所マスタに登録されていません。',
    'WLP029-0014': '[xxxxx] は支部マスタに登録されていません。',
    'WLP029-0015': '[xxxxx] の値が不正です。',
    'WLP029-0016': '[xxxxx] は yyyyy 以上を入力してください。',
    'WLP029-0017': '割当確定＋仮割当の人数が [募集人数] を超えます。',
    'WLP029-0018': '[従事可能曜日フラグ（日～土）] のいずれに値を入力してください。',
    'WLP029-0019':
        '[スキル（所得税／法人税／資産税／消費税／会社法／財務会計／譲渡・山林／贈与税）] のすべてに値を入力してください。（[応募時必須入力項目フラグ] が設定されています。）',
    'WLP029-0020': '[xxxxx] は入力しないでください。yyyyy',
    'WLP029-0021': '[xxxxx] が既に登録されています。',
    'WLP029-0022': '[xxxxx] がファイル内に存在します。',
    'WLP029-0023': '[割当明細] の [従事フラグ] は「1（従事済み）」にしてください。',
    'WLP029-0024': 'この事業に対する一括割当を実行中です。しばらくお待ち下さい。（[xxxxx] 開始）',
    'WLP029-0025': '自支部（連）のデータではありません。',
    'WLP029-0026': '[xxxxx] と [yyyyy] はどちらか一方を「zzzzz」にしてください。',
    'WLP029-0027': '[従事済みフラグ] が「1（従事登録済み）」ですが、[事績] が登録されていません。',
    'WLP029-0028': 'この従事に対する登録はできません。',
    'WLP029-0029': '登録番号と会員区分の組み合わせが正しくありません。',
    'WLP029-0030': '懲戒処分により業務停止中、または業務禁止中の会員です。',
    'SYSTEM-5101': '[xxxxx] を入力してください。',
    'SYSTEM-5102': '[xxxxx] には [yyyyy] のみ入力可能です。zzzzz',
    'SYSTEM-5104': '[xxxxx] の入力範囲が不正です。',
    'SYSTEM-5108': '[xxxxx] には [yyyyy] を入力してください。',
    'SYSTEM-6102': '対象ファイルには xxxxx 形式を指定してください。',
    'SYSTEM-6103': '対象ファイルにはデータが存在しません。',
    'SYSTEM-6104': '対象ファイルのフォーマットが不正です。',
    'SYSTEM-6105': '対象ファイルにエラーが見つかりました。',
    'SYSTEM-7001': '無効な [xxxxx] です。',
    'SYSTEM-7002': '[xxxxx] が登録されていません。'
};

// 確認ダイアログ（ToBe の文言）
const CONFIRM_REGISTER = { title: '登録確認', message: 'ファイルを取り込みます。よろしいですか？' };

/**
 * メッセージの文言を作る。置換値を省略した置換文字は空にする【要確認 C-15】
 * @param {string} id メッセージ ID
 * @param {string} [x] xxxxx の置換値
 * @param {string} [y] yyyyy の置換値
 * @param {string} [z] zzzzz の置換値
 */
function getMessage(id, x = '', y = '', z = '') {
    const template = TEMPLATES[id];
    if (template === undefined) {
        return id;
    }
    return template.split('xxxxx').join(x).split('yyyyy').join(y).split('zzzzz').join(z);
}

// ============================================================
// コード変換表
// ============================================================
/**
 * 従事事業CSV登録 コード変換表
 * CSV の値（現行コード）→ 選択リストの API 参照名。設計書「26」のコード変換表。
 * ・ファイル内チェックのコード値チェック（No.9）は、この表にコードがあるかで判定する。
 * ・登録時の変換も、この表（toApiValue）だけを使う。
 * 【要確認 D-54】保持場所が決まるまでここに直接記載する。
 * 【要確認 D-53】選択リストの API 参照名がコードに変更された場合は、値をコードと同じにする（または toApiValue でコードをそのまま返す）。
 */
const CODE_TABLE = {
    // 謝金支払方法
    syakinHoho: { 0: '謝金無', 1: '振込個人', 2: '振込支部', 3: '現金', 4: '為替' },
    // 謝金単位区分（現行コード種別 0115）
    syakinTani: { 0: '日数単位', 1: '件数単位' },
    // 謝金額内税・外税、交通費額内税・外税（現行コード種別 0090）
    zei: { 0: '外税', 1: '内税' },
    // 交通費支払方法（現行コード種別 0026）
    kotuhiHoho: { 0: '交通費無', 1: '振込個人', 2: '振込支部', 3: '現金', 4: '為替', 5: '旅費規程' },
    // 交通費課税区分（現行コード種別 0027）
    kazei: { 0: '課税無', 1: '課税有' },
    // 支払調書区分（謝金・交通費。現行コード種別 0028・0029）
    tyosyo: {
        24: '相談謝金',
        13: '講演料',
        20: '弁護士報酬',
        21: '司法書士報酬',
        22: '社会保険労務士報酬',
        29: 'その他（２号）',
        19: 'その他（１号）',
        10: '原稿料',
        16: '挿絵料'
    },
    // 応募時必須入力項目フラグ
    hisuFlag: { 0: '省略可', 1: '必須' },
    // 応募時任意入力項目フラグ
    niniFlag: { 0: '禁止', 1: '許可' },
    // インターネット募集区分
    netKubun: { 0: '募集しない', 1: '募集する' },
    // インターネット募集対象
    netTaisyo: { 0: '限定無し', 1: '自支部のみ' },
    // 支部ユーザ操作（現行コード種別 0093）
    sibuUserSosa: { 1: '可能', 2: '不可' },
    // 会員区分（現行コード種別 0010）
    kaiinKubun: { 1: '会員', 2: '非会員' },
    // 従事可能曜日フラグ（API 参照名＝コード）
    yobiFlag: { 0: '0', 1: '1' },
    // 従事経験（API 参照名＝コード）
    keiken: { 1: '1', 2: '2' },
    // スキル（値は同じ）
    skill: { 1: '1', 2: '2', 3: '3', 4: '4', 5: '5' },
    // 割当の追加・割当・確定・従事・今回フラグ【要確認 D-21】API 参照名が 0/1 の想定
    wariFlag: { 0: '0', 1: '1' },
    // 税理士区分（グローバル値セット「税理士区分」）【要確認 D-22】7・8 は仮の対応
    zeirisi: {
        1: '開業税理士（ハ）',
        2: '本店社員（イ）',
        3: '支店社員（イ）',
        4: '所属開業（ロ）',
        5: '所属本店（ロ）',
        6: '所属支店（ロ）',
        7: '親税理士',
        8: '代表社員'
    },
    // 謝金振込先種別（現行コード種別 0121。3 は欠番）
    furikomiSyubetu: { 1: '普通', 2: '当座', 4: '貯蓄預金' },
    // 口座指定（チェックボックス）
    kozaSitei: { 0: false, 1: true }
};

/** コードが変換表にあるか（No.9） */
function isValidCode(codeKey, value) {
    const table = CODE_TABLE[codeKey];
    return table !== undefined && Object.prototype.hasOwnProperty.call(table, value);
}

/** CSV のコードを選択リストの API 参照名に変換する（登録時に使用。空は null） */
function toApiValue(codeKey, value) {
    if (value === '' || value === null || value === undefined) {
        return null;
    }
    return CODE_TABLE[codeKey][value];
}

// ============================================================
// ファイルレイアウト
// ============================================================
/**
 * 従事事業CSV登録 ファイルレイアウト
 * 新機能設計書「別紙_xxxファイルレイアウト」（設計書「26」6・7 章）の列順・桁・必須。
 * ・req：必須（No.6 で判定）。条件付き必須の項目は false とし、各ファイルのチェックで判定する。
 * ・len：桁（No.7）。数値の項目は数字の桁数で判定する。
 * ・type：形式（No.8）。code はコード変換表（CODE_TABLE）のキー（No.9）。
 */

// 形式
const TYPE = {
    TEXT: 'text', // 文字（桁のみチェック）
    NUM: 'num', // 半角数字
    SIGNED: 'signed', // 半角数字（先頭のマイナスを許可。マイナスは各ファイルのチェックで判定する）
    DECIMAL: 'decimal', // 半角数字（整数 3 桁・小数 2 桁まで）
    DATE: 'date', // YYYYMMDD
    TIME: 'time', // HHmm
    YEAR: 'year', // 半角数字 4 桁
    CODE: 'code', // コード値
    NONE: 'none' // 入力不可（No.72 で判定するため単項目チェックは行わない）
};

const col = (name, label, len, type, options = {}) => ({
    name,
    label,
    len,
    type,
    req: options.req === true,
    code: options.code,
    zeroOk: options.zeroOk === true // コード値チェックで「0」をエラーにしない（各ファイルのチェックで判定する）
});

// 事業キー（全ファイルの先頭 3 列）
const KEY_COLUMNS = [
    col('jigyoNo', '従事事業No', 7, TYPE.NUM, { req: true }),
    col('basyoNo', '従事場所No', 10, TYPE.TEXT, { req: true }),
    col('nendo', '実施年度', 4, TYPE.YEAR, { req: true })
];

// 従事事業（FLP006、32 列）
const JIGYO = [
    ...KEY_COLUMNS,
    col('jigyoName', '従事事業名', 32, TYPE.TEXT, { req: true }),
    col('jigyoKubun', '事業区分', 3, TYPE.NUM, { req: true }), // TODO コード値チェック（事業区分の一覧 未入手）
    col('sibuCode', '支部コード', 3, TYPE.NUM, { req: true }),
    col('syakinHoho', '謝金支払方法', 1, TYPE.CODE, { req: true, code: 'syakinHoho' }),
    col('syakinTani', '謝金単位区分', 1, TYPE.CODE, { req: true, code: 'syakinTani' }),
    col('syakingaku', '謝金額', 12, TYPE.NUM), // 条件付き必須（No.10）
    col('syakinZei', '謝金額内税・外税', 1, TYPE.CODE, { code: 'zei' }),
    col('kotuhiHoho', '交通費支払方法', 1, TYPE.CODE, { req: true, code: 'kotuhiHoho' }),
    col('kotuhiKazei', '交通費課税区分', 1, TYPE.CODE, { req: true, code: 'kazei' }),
    col('kotuhigaku', '交通費額', 12, TYPE.NUM), // 条件付き必須（No.11）
    col('kotuhiZei', '交通費額内税・外税', 1, TYPE.CODE, { code: 'zei' }),
    col('tyosyoSyakin', '支払調書区分（謝金）', 2, TYPE.CODE, { code: 'tyosyo', zeroOk: true }), // 条件付き（No.12）
    col('tyosyoSyakinName', '支払調書区分名称（謝金）', 20, TYPE.TEXT),
    col('tyosyoKotuhi', '支払調書区分（交通費）', 2, TYPE.CODE, { code: 'tyosyo', zeroOk: true }), // 条件付き（No.13）
    col('tyosyoKotuhiName', '支払調書区分名称（交通費）', 20, TYPE.TEXT),
    col('biko', '備考', 256, TYPE.TEXT),
    col('hisuYobi', '応募時必須入力項目フラグ（従事可能曜日）', 1, TYPE.CODE, { code: 'hisuFlag' }),
    col('hisuKanoHi', '応募時必須入力項目フラグ（従事可能日）', 1, TYPE.CODE, { code: 'hisuFlag' }),
    col('hisuKiboNisu', '応募時必須入力項目フラグ（希望従事日数）', 1, TYPE.CODE, { code: 'hisuFlag' }),
    col('hisuSkill', '応募時必須入力項目フラグ（スキル（5段階））', 1, TYPE.CODE, { code: 'hisuFlag' }),
    col('niniSkill', '応募時任意入力項目フラグ（スキル（5段階））', 1, TYPE.CODE, { code: 'niniFlag' }),
    col('niniSkillToki', '応募時任意入力項目フラグ（スキル特記事項）', 1, TYPE.CODE, { code: 'niniFlag' }),
    col('niniTyosyo', '応募時任意入力項目フラグ（主な著書、論文）', 1, TYPE.CODE, { code: 'niniFlag' }),
    col('niniSodan', '応募時任意入力項目フラグ（相談科目）', 1, TYPE.CODE, { code: 'niniFlag' }),
    col('netKubun', 'インターネット募集区分', 1, TYPE.CODE, { code: 'netKubun' }),
    col('netTaisyo', 'インターネット募集対象', 1, TYPE.CODE, { code: 'netTaisyo' }), // 条件付き（No.16）
    // 【要確認 D-34】新レイアウトの列順（30 列目 To、31 列目 From）。実際は逆の可能性あり
    col('netKikanTo', 'インターネット募集期間To', 8, TYPE.DATE),
    col('netKikanFrom', 'インターネット募集期間From', 8, TYPE.DATE),
    col('sibuUserSosa', '支部ユーザ操作', 1, TYPE.CODE, { code: 'sibuUserSosa' }) // 事務局ユーザのみ必須（No.17）
];

// 従事事業明細（FLP007、8 列）
const MEISAI = [
    ...KEY_COLUMNS,
    col('jisiNengapi', '実施年月日', 8, TYPE.DATE, { req: true }),
    col('bosyuNinzu', '募集人数', 3, TYPE.NUM, { req: true }),
    col('kaisiJikoku', '開始時間', 4, TYPE.TIME),
    col('syuryoJikoku', '終了時間', 4, TYPE.TIME),
    col('biko', '備考', 50, TYPE.TEXT)
];

// 従事事業応募（FLP008、30 列）
const OUBO = [
    ...KEY_COLUMNS,
    col('torokuNo', '登録番号', 7, TYPE.TEXT, { req: true }),
    col('uketukeNo', '受付番号', 10, TYPE.NUM, { req: true }),
    col('kaiinKubun', '会員区分', 1, TYPE.CODE, { req: true, code: 'kaiinKubun' }),
    col('yobiSun', '従事可能曜日フラグ（日）', 1, TYPE.CODE, { code: 'yobiFlag' }),
    col('yobiMon', '従事可能曜日フラグ（月）', 1, TYPE.CODE, { code: 'yobiFlag' }),
    col('yobiTue', '従事可能曜日フラグ（火）', 1, TYPE.CODE, { code: 'yobiFlag' }),
    col('yobiWed', '従事可能曜日フラグ（水）', 1, TYPE.CODE, { code: 'yobiFlag' }),
    col('yobiThu', '従事可能曜日フラグ（木）', 1, TYPE.CODE, { code: 'yobiFlag' }),
    col('yobiFri', '従事可能曜日フラグ（金）', 1, TYPE.CODE, { code: 'yobiFlag' }),
    col('yobiSat', '従事可能曜日フラグ（土）', 1, TYPE.CODE, { code: 'yobiFlag' }),
    col('kiboNisu', '希望従事日数', 3, TYPE.NUM),
    col('jujiKeiken', '従事経験', 1, TYPE.CODE, { code: 'keiken' }),
    col('skillSyotoku', 'スキル（所得税）', 1, TYPE.CODE, { code: 'skill' }),
    col('skillHojin', 'スキル（法人税）', 1, TYPE.CODE, { code: 'skill' }),
    col('skillSisan', 'スキル（資産税）', 1, TYPE.CODE, { code: 'skill' }),
    col('skillSyohi', 'スキル（消費税）', 1, TYPE.CODE, { code: 'skill' }),
    col('skillKaisyaho', 'スキル（会社法）', 1, TYPE.CODE, { code: 'skill' }),
    col('skillZaimu', 'スキル（財務会計）', 1, TYPE.CODE, { code: 'skill' }),
    col('skillJoto', 'スキル（譲渡・山林）', 1, TYPE.CODE, { code: 'skill' }),
    col('skillZoyo', 'スキル（贈与税）', 1, TYPE.CODE, { code: 'skill' }),
    col('skillToki', 'スキル特記事項', 100, TYPE.TEXT),
    col('tyosyoRonbun', '主な著書、論文', 100, TYPE.TEXT),
    col('sodanKamoku', '相談科目', 32, TYPE.TEXT),
    col('biko', '備考', 256, TYPE.TEXT),
    col('tel', '連絡先（TEL）', 14, TYPE.TEXT), // 形式は No.37
    col('fax', '連絡先（FAX）', 14, TYPE.TEXT), // 形式は No.37
    col('mail', '連絡先（Mail）', 256, TYPE.TEXT)
];

// 従事事業応募明細（FLP009、5 列）
const OUBO_MEISAI = [
    ...KEY_COLUMNS,
    col('torokuNo', '登録番号', 7, TYPE.TEXT, { req: true }),
    col('jujiKanoBi', '従事可能日', 8, TYPE.DATE, { req: true })
];

// 従事事業割当（FLP010、11 列）。フラグは省略時 0
const WARIATE = [
    ...KEY_COLUMNS,
    col('jujiNengapi', '従事年月日', 8, TYPE.DATE, { req: true }),
    col('torokuNo', '登録番号', 7, TYPE.TEXT, { req: true }),
    col('tuikaFlag', '追加フラグ', 1, TYPE.CODE, { code: 'wariFlag' }),
    col('wariFlag', '割当フラグ', 1, TYPE.CODE, { code: 'wariFlag' }),
    col('kakuteiFlag', '確定フラグ', 1, TYPE.CODE, { code: 'wariFlag' }),
    col('jujiFlag', '従事フラグ', 1, TYPE.CODE, { code: 'wariFlag' }),
    col('konkaiFlag', '今回フラグ', 1, TYPE.CODE, { code: 'wariFlag' }),
    col('biko', '備考', 100, TYPE.TEXT) // 【要確認 D-35】新レイアウト 100 桁
];

// 従事事業実績（FLP011、36 列）
const JISSEKI = [
    ...KEY_COLUMNS,
    col('jujiNengapi', '従事年月日', 8, TYPE.DATE, { req: true }),
    col('torokuNo', '登録番号', 7, TYPE.TEXT, { req: true }),
    col('zeirisiKubun', '税理士区分', 1, TYPE.CODE, { req: true, code: 'zeirisi' }),
    col('oyaNo', '親税理士番号', 7, TYPE.TEXT), // 条件付き（No.67）
    col('hojinNo', '法人番号', 6, TYPE.TEXT), // 条件付き（No.67）
    col('hojinEdaban', '法人枝番', 3, TYPE.TEXT), // 条件付き（No.67）
    col('jujiJiseki', '従事事績', 5, TYPE.DECIMAL, { req: true }),
    col('syakingaku', '謝金額', 12, TYPE.SIGNED),
    col('syakinSyohi', '謝金消費税額', 12, TYPE.SIGNED),
    col('syakinGensen', '謝金源泉税額', 12, TYPE.SIGNED),
    col('ginkoCode', '謝金振込先銀行コード', 4, TYPE.NUM),
    col('sitenCode', '謝金振込先支店コード', 3, TYPE.NUM),
    col('furikomiSyubetu', '謝金振込先種別', 1, TYPE.CODE, { code: 'furikomiSyubetu' }),
    col('kozaNo', '謝金振込先口座番号', 7, TYPE.NUM),
    col('kozaMeigi', '謝金振込先口座名義', 30, TYPE.TEXT),
    col('syakinHoho', '謝金支払方法', 1, TYPE.CODE, { code: 'syakinHoho' }),
    col('kotuhigaku', '交通費額', 12, TYPE.SIGNED),
    col('kotuhiSyohi', '交通費消費税額', 12, TYPE.SIGNED),
    col('kotuhiGensen', '交通費源泉税額', 12, TYPE.SIGNED),
    col('kotuhiHoho', '交通費支払方法', 1, TYPE.CODE, { code: 'kotuhiHoho' }),
    col('kotuhiKazei', '交通費課税区分', 1, TYPE.CODE, { code: 'kazei' }),
    col('tyosyoSyakin', '支払調書区分（謝金）', 2, TYPE.CODE, { code: 'tyosyo' }),
    col('tyosyoSyakinName', '支払調書区分名称（謝金）', 20, TYPE.TEXT),
    col('tyosyoKotuhi', '支払調書区分（交通費）', 2, TYPE.CODE, { code: 'tyosyo' }),
    col('tyosyoKotuhiName', '支払調書区分名称（交通費）', 20, TYPE.TEXT),
    col('biko', '備考', 256, TYPE.TEXT),
    col('siharaiNengapi', '支払年月日', 8, TYPE.NONE),
    col('siharaiJikoDate', '支払出力実行日', 8, TYPE.NONE),
    col('siharaiJikoTime', '支払出力実行時刻', 5, TYPE.NONE),
    col('siharaiUserId', '支払出力ユーザID', 5, TYPE.NONE),
    col('kozaSitei', '口座指定', 1, TYPE.CODE, { code: 'kozaSitei' }),
    col('tyoseiKingaku', '調整金額', 12, TYPE.SIGNED),
    col('furikomigaku', '振込額', 12, TYPE.SIGNED)
];

// 登録対象（画面の行の順）
const FILE_KEY = {
    JIGYO: 'jigyo',
    MEISAI: 'meisai',
    OUBO: 'oubo',
    OUBO_MEISAI: 'ouboMeisai',
    WARIATE: 'wariate',
    JISSEKI: 'jisseki'
};

const LAYOUTS = {
    [FILE_KEY.JIGYO]: JIGYO,
    [FILE_KEY.MEISAI]: MEISAI,
    [FILE_KEY.OUBO]: OUBO,
    [FILE_KEY.OUBO_MEISAI]: OUBO_MEISAI,
    [FILE_KEY.WARIATE]: WARIATE,
    [FILE_KEY.JISSEKI]: JISSEKI
};

// ============================================================
// CSV の読込
// ============================================================
/**
 * 従事事業CSV登録 CSV の読込
 * 【確認済み】A-4 Shift_JIS／A-9 カンマ区切り・囲み文字なし／A-10 CRLF／D-49 見出し行あり
 * 【仮】A-11 空行（カンマのみの行を含む。Excel で保存すると空行がカンマのみになるため）は末尾・途中とも読み飛ばす
 *       D-49 行番号は見出し行を 1 行目とするファイルの行番号
 */
const ENCODING = 'shift_jis';
const DELIMITER = ',';
const LINE_BREAK = /\r\n|\n/; // CRLF（LF のみの改行も受け付ける）
const HEADER_LINES = 1;
const BLANK_LINE = /^,*$/; // 空行・カンマのみの行

function readAsArrayBuffer(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsArrayBuffer(file);
    });
}

/**
 * CSV ファイルを読み込む
 * @param {File} file
 * @returns {Promise<{ok: boolean, rows: Array<{lineNo: number, values: string[]}>}>}
 *   ok：false はファイルが読み込めない（Shift_JIS として不正なバイトを含む等）
 */
async function readCsv(file) {
    let text;
    try {
        const buffer = await readAsArrayBuffer(file);
        text = new TextDecoder(ENCODING, { fatal: true }).decode(buffer);
    } catch (e) {
        return { ok: false, rows: [] };
    }

    const rows = [];
    text.split(LINE_BREAK).forEach((line, index) => {
        const lineNo = index + 1;
        if (lineNo <= HEADER_LINES || BLANK_LINE.test(line)) {
            return;
        }
        rows.push({ lineNo, values: line.split(DELIMITER) });
    });
    return { ok: true, rows };
}

// ============================================================
// エラーの収集・出力
// ============================================================
/**
 * 従事事業CSV登録 エラーの収集・出力
 * 【要確認 F-8】当面は行単位のエラーをブラウザのコンソールログに出力する。出力先を変えるときは outputLog だけを差し替える。
 * ログの形式：
 *   【ファイル内チェック】エラー 2 件
 *   取り込みファイル1.csv
 *       523行目_[従事場所No] には [半角数字] のみ入力可能です。
 */

const KUBUN = {
    CATEGORY1: 1,
    CATEGORY2: 2
};

// 区分の名称（設計書「31」前提 4。2 つの区分を合わせて「入力チェック」と呼ぶ）
const KUBUN_NAMES = {
    [KUBUN.CATEGORY1]: '① ファイル内チェック',
    [KUBUN.CATEGORY2]: '② 整合性チェック'
};

const TITLES = {
    [KUBUN.CATEGORY1]: `【${KUBUN_NAMES[KUBUN.CATEGORY1]}】`,
    [KUBUN.CATEGORY2]: `【${KUBUN_NAMES[KUBUN.CATEGORY2]}】`
};

/**
 * エラー 1 件
 * @param {object} file    対象ファイル（fileKey・fileName・order・label）
 * @param {number} lineNo  行番号
 * @param {number} checkNo チェック No.（設計書「31」）
 * @param {string} messageId メッセージ ID
 * @param {string} [x] @param {string} [y] @param {string} [z] 置換値
 */
function createError(kubun, file, lineNo, checkNo, messageId, x, y, z) {
    return {
        kubun,
        fileKey: file.fileKey,
        label: file.label,
        fileName: file.fileName,
        order: file.order,
        lineNo,
        checkNo,
        messageId,
        message: getMessage(messageId, x, y, z)
    };
}

/** ログの文字列を作る（ファイルの順 → 行番号。同じ行はチェックした順＝項目の順） */
function formatLog(kubun, errors) {
    const title = TITLES[kubun];
    if (errors.length === 0) {
        return `${title}エラーなし`;
    }
    const sorted = [...errors].sort((a, b) => a.order - b.order || a.lineNo - b.lineNo);
    const lines = [`${title}エラー ${errors.length} 件`];
    let currentFile = null;
    sorted.forEach((e) => {
        if (e.fileKey !== currentFile) {
            currentFile = e.fileKey;
            lines.push(e.fileName);
        }
        lines.push(`    ${e.lineNo}行目_${e.message}`);
    });
    return lines.join('\n');
}

/** ログに出力する（詳細なエラー情報はデバッグ用に console.debug へ） */
function outputLog(kubun, errors) {
    // eslint-disable-next-line no-console
    console.log(formatLog(kubun, errors));
    if (errors.length > 0) {
        // eslint-disable-next-line no-console
        console.debug(errors);
    }
}

// ============================================================
// エラーログ（ポップアップ・ダウンロード）
// ============================================================
/**
 * 行単位のエラーがある場合、ポップアップに区分ごとの結果・ファイルごとの件数を表示し、
 * コンソールログと同じ内容をテキストファイルでダウンロードできるようにする。【要確認 F-8】
 */
const ERROR_LOG = {
    title: 'ファイル一括登録 エラーログ',
    fileName: 'ファイル一括登録_エラーログ_',
    newLine: '\r\n', // Windows のメモ帳で開けるよう CRLF・BOM 付き UTF-8 とする
    bom: '\uFEFF'
};

// ポップアップに表示する区分の説明
const KUBUN_DESCRIPTIONS = {
    [KUBUN.CATEGORY1]: 'ファイルの行ごとに、必須・桁数・形式・コード値・項目の組み合わせ、ファイル内の重複を確認します。',
    [KUBUN.CATEGORY2]:
        'ファイル内チェックでエラーがない場合のみ、他のファイルや登録済みデータとの整合性（マスタ・親データの存在、登録済みデータとの重複など）を確認します。'
};

const pad2 = (n) => String(n).padStart(2, '0');

function formatDateTime(d) {
    return `${d.getFullYear()}/${pad2(d.getMonth() + 1)}/${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

function formatFileDateTime(d) {
    return `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}_${pad2(d.getHours())}${pad2(d.getMinutes())}${pad2(d.getSeconds())}`;
}

/**
 * エラーログを作る
 * @param {Array<{kubun: number, errors: Array}>} results 行ったチェック区分の結果（実行順。エラーがあった区分で終了するため最後がエラーの区分）
 * @returns {{kubun, total, categories, files, fileName, text}}
 */
function createErrorLog(results, now = new Date()) {
    const failed = results[results.length - 1];
    const byFile = new Map();
    failed.errors.forEach((e) => {
        const f = byFile.get(e.fileKey) || { key: e.fileKey, order: e.order, label: e.label, fileName: e.fileName, count: 0 };
        f.count++;
        byFile.set(e.fileKey, f);
    });
    const categories = Object.values(KUBUN).map((kubun) => {
        const result = results.find((r) => r.kubun === kubun);
        let resultLabel = '未実施';
        if (result) {
            resultLabel = result.errors.length > 0 ? `エラー ${result.errors.length} 件` : 'エラーなし';
        }
        return {
            kubun,
            name: KUBUN_NAMES[kubun],
            description: KUBUN_DESCRIPTIONS[kubun],
            result: resultLabel,
            resultClass: result && result.errors.length > 0 ? 'slds-text-color_error' : 'slds-text-color_weak'
        };
    });
    const lines = [ERROR_LOG.title, `出力日時：${formatDateTime(now)}`];
    results.forEach((r) => lines.push('', formatLog(r.kubun, r.errors)));
    return {
        kubun: failed.kubun,
        total: failed.errors.length,
        categories,
        files: [...byFile.values()].sort((a, b) => a.order - b.order),
        fileName: `${ERROR_LOG.fileName}${formatFileDateTime(now)}.txt`,
        text: lines.join('\n').replace(/\n/g, ERROR_LOG.newLine)
    };
}

/** テキストファイルをダウンロードする */
function downloadText(fileName, text) {
    const content = ERROR_LOG.bom + text;
    const link = document.createElement('a');
    let objectUrl = null;
    try {
        objectUrl = URL.createObjectURL(new Blob([content], { type: 'text/plain;charset=utf-8' }));
        link.href = objectUrl;
    } catch (e) {
        link.href = `data:text/plain;charset=utf-8,${encodeURIComponent(content)}`;
    }
    link.download = fileName;
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    if (objectUrl) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
    }
}

// ============================================================
// ファイル内チェック
// ============================================================
/**
 * 従事事業CSV登録 ファイル内チェック
 * 対象ファイルの 1 行（キー重複はファイル内）だけで判定するチェック（設計書「31」区分 1）。
 * ・全ファイル・全行・全チェックを行う（エラーがあっても次の行・ファイルを続ける）。
 * ・原因のエラーのみ出力する（「31」前提 4 (3)）：
 *     列数が一致しない行は他のチェックを行わない／単項目は 1 項目につき No.6→7→8→9 の最初のエラーのみ／
 *     相関・範囲チェックは参照する項目が単項目でエラーなら行わない／キー重複はキー項目がエラーの行を対象外とする。
 * ・No.1～4（ファイル単位）は画面（コンポーネント）で判定する。
 */

// ユーザ種別（Juj_JigyoCsvUploaderController.getLoginUserInfo の userType）
const USER_TYPE = {
    SUPER: 'SUPER', // スーパーユーザ
    JIMUKYOKU: 'JIMUKYOKU', // 事務局
    SIBUREN: 'SIBUREN', // 支部連
    SIBU: 'SIBU' // 支部
};

const HONKAI_SIBU_CODE = '000'; // 本会の支部コード【要確認 D-31】
const CODE_NASI = '0'; // 謝金支払方法「謝金無」・交通費支払方法「交通費無」
const CODE_FURIKOMI_KOJIN = '1'; // 支払方法「振込個人」
const CODE_BOSYU_SURU = '1'; // インターネット募集区分「募集する」
const CODE_SOSA_KANO = '1'; // 支部ユーザ操作「可能」
const FLAG_ON = '1';
const FLAG_OFF = '0';

// ---------- 判定の部品 ----------
const isEmpty = (v) => v === '';
const isZeroOrEmpty = (v) => v === '' || Number(v) === 0;
const toNumber = (v) => (v === '' ? 0 : Number(v));
// 実施年度内：実施年度の 4/1 ≦ 日付 ≦ 翌年 3/31（日付は YYYYMMDD）
const inNendo = (nendo, date) => date >= `${nendo}0401` && date <= `${Number(nendo) + 1}0331`;

function isValidDate(v) {
    if (!/^[0-9]{8}$/.test(v)) {
        return false;
    }
    const y = Number(v.slice(0, 4));
    const m = Number(v.slice(4, 6));
    const d = Number(v.slice(6, 8));
    const date = new Date(y, m - 1, d);
    return date.getFullYear() === y && date.getMonth() === m - 1 && date.getDate() === d;
}

// 形式（No.8）。label は SYSTEM-5102 の yyyyy
const FORMATS = {
    [TYPE.NUM]: { test: (v) => /^[0-9]+$/.test(v), label: '半角数字' },
    [TYPE.SIGNED]: { test: (v) => /^-?[0-9]+$/.test(v), label: '半角数字' },
    [TYPE.DECIMAL]: { test: (v) => /^[0-9]{1,3}(\.[0-9]{1,2})?$/.test(v), label: '半角数字' },
    [TYPE.DATE]: { test: isValidDate, label: '日付' },
    [TYPE.TIME]: { test: (v) => /^([01][0-9]|2[0-3])[0-5][0-9]$/.test(v), label: '時間' },
    [TYPE.YEAR]: { test: (v) => /^[0-9]{4}$/.test(v), label: '年度' }
};

// 桁数（No.7）。数値の項目はマイナス・小数点を除いた桁数
const NUMERIC_TYPES = new Set([TYPE.NUM, TYPE.SIGNED, TYPE.DECIMAL]);
const lengthOf = (column, v) => (NUMERIC_TYPES.has(column.type) ? v.replace(/[-.]/g, '').length : v.length);

/** 単項目チェック（No.6～9）。最初のエラーのみ返す */
function checkItem(column, v) {
    if (isEmpty(v)) {
        return column.req ? { no: 6, id: 'SYSTEM-5101', x: column.label } : null;
    }
    if (column.type === TYPE.NONE) {
        return null;
    }
    if (lengthOf(column, v) > column.len) {
        return { no: 7, id: 'WLP029-0015', x: column.label };
    }
    const format = FORMATS[column.type];
    if (format && !format.test(v)) {
        return { no: 8, id: 'SYSTEM-5102', x: column.label, y: format.label };
    }
    if (column.type === TYPE.CODE && !(column.zeroOk && v === '0') && !isValidCode(column.code, v)) {
        return { no: 9, id: 'WLP029-0015', x: column.label };
    }
    return null;
}

// ---------- 相関・範囲チェック（ファイルごと） ----------
// refs：参照する項目（いずれかが単項目でエラーなら行わない）
// run(d, ctx, L, bad)：d＝行の値、ctx＝取込ユーザ、L＝項目名、bad＝単項目でエラーの項目。[メッセージID, x, y, z] の配列を返す

const ZEIRISI_GROUPS = {
    1: 'A', // 開業税理士
    7: 'A', // 非会員（個人）
    8: 'A', // 非会員（法人）
    4: 'B', // 補助開業
    2: 'C', // 本店社員
    3: 'C', // 支店社員
    5: 'C', // 補助本店
    6: 'C' // 補助支店
};
const NG = 'NG'; // 入力不可
const REQ = 'REQ'; // 必須
// No.67 の税理士区分ごとの入力可否【要確認 D-22】
const ZEIRISI_RULES = {
    A: { oyaNo: NG, hojinNo: NG, hojinEdaban: NG },
    B: { oyaNo: REQ, hojinNo: NG, hojinEdaban: NG },
    C: { oyaNo: NG, hojinNo: REQ, hojinEdaban: REQ }
};
// No.69 謝金源泉税額を入力できる税理士区分（開業税理士・補助開業・非会員（個人））【要確認 D-28】
const GENSEN_KUBUN = new Set(['1', '4', '7']);
const JISSEKI_AMOUNTS = ['syakingaku', 'syakinSyohi', 'syakinGensen', 'kotuhigaku', 'kotuhiSyohi', 'kotuhiGensen'];
const FURIKOMI_ITEMS = ['ginkoCode', 'sitenCode', 'furikomiSyubetu', 'kozaNo', 'kozaMeigi'];
const SIHARAI_ITEMS = ['siharaiNengapi', 'siharaiJikoDate', 'siharaiJikoTime', 'siharaiUserId'];
const TEL_PATTERN = /^[0-9-]+$/;

const ROW_CHECKS = {
    [FILE_KEY.JIGYO]: [
        {
            no: 10,
            refs: ['syakinHoho', 'syakingaku'],
            run: (d, ctx, L) => {
                if (d.syakinHoho !== CODE_NASI && isEmpty(d.syakingaku)) {
                    return [['SYSTEM-5101', L.syakingaku]];
                }
                if (d.syakinHoho === CODE_NASI && !isZeroOrEmpty(d.syakingaku)) {
                    return [['SYSTEM-5108', L.syakingaku, '0または空']];
                }
                return [];
            }
        },
        {
            no: 11, // 【要確認 D-50】旅費規程
            refs: ['kotuhiHoho', 'kotuhigaku'],
            run: (d, ctx, L) => {
                if (d.kotuhiHoho !== CODE_NASI && isEmpty(d.kotuhigaku)) {
                    return [['SYSTEM-5101', L.kotuhigaku]];
                }
                if (d.kotuhiHoho === CODE_NASI && !isZeroOrEmpty(d.kotuhigaku)) {
                    return [['SYSTEM-5108', L.kotuhigaku, '0または空']];
                }
                return [];
            }
        },
        {
            no: 12,
            refs: ['syakinHoho', 'tyosyoSyakin'],
            run: (d, ctx, L) => {
                if (d.syakinHoho !== CODE_NASI && (isEmpty(d.tyosyoSyakin) || d.tyosyoSyakin === '0')) {
                    return [['SYSTEM-5108', L.tyosyoSyakin, '0以外']];
                }
                if (d.syakinHoho === CODE_NASI && !isEmpty(d.tyosyoSyakin)) {
                    return [['SYSTEM-5108', L.tyosyoSyakin, '空']];
                }
                return [];
            }
        },
        {
            no: 13, // 【要確認 D-33】交通費課税区分を条件に含めるか
            refs: ['kotuhiHoho', 'tyosyoKotuhi'],
            run: (d, ctx, L) => {
                if (d.kotuhiHoho !== CODE_NASI && (isEmpty(d.tyosyoKotuhi) || d.tyosyoKotuhi === '0')) {
                    return [['SYSTEM-5108', L.tyosyoKotuhi, '0以外']];
                }
                if (d.kotuhiHoho === CODE_NASI && !isEmpty(d.tyosyoKotuhi)) {
                    return [['SYSTEM-5108', L.tyosyoKotuhi, '空']];
                }
                return [];
            }
        },
        {
            no: 14,
            refs: ['hisuYobi', 'hisuKanoHi'],
            run: (d, ctx, L) =>
                d.hisuYobi === FLAG_ON && d.hisuKanoHi === FLAG_ON
                    ? [['WLP029-0012', L.hisuYobi, L.hisuKanoHi, FLAG_OFF]]
                    : []
        },
        {
            no: 15,
            refs: ['hisuSkill', 'niniSkill'],
            run: (d, ctx, L) =>
                d.hisuSkill === FLAG_ON && d.niniSkill === FLAG_ON
                    ? [['WLP029-0012', L.hisuSkill, L.niniSkill, FLAG_OFF]]
                    : []
        },
        {
            no: 16, // 【要確認 D-34】募集期間の列順
            refs: ['netKubun'],
            run: (d, ctx, L, bad) => {
                if (d.netKubun !== CODE_BOSYU_SURU) {
                    return [];
                }
                const result = ['netTaisyo', 'netKikanFrom', 'netKikanTo']
                    .filter((name) => isEmpty(d[name]))
                    .map((name) => ['SYSTEM-5101', L[name]]);
                const from = d.netKikanFrom;
                const to = d.netKikanTo;
                if (!isEmpty(from) && !isEmpty(to) && !bad.has('netKikanFrom') && !bad.has('netKikanTo') && from > to) {
                    result.push(['SYSTEM-5104', 'インターネット募集期間']);
                }
                return result;
            }
        },
        {
            no: 17,
            refs: ['sibuUserSosa'],
            run: (d, ctx, L) => (ctx.isJimukyoku && isEmpty(d.sibuUserSosa) ? [['SYSTEM-5101', L.sibuUserSosa]] : [])
        },
        {
            no: 18, // 【要確認 D-31】
            refs: ['sibuCode', 'sibuUserSosa'],
            run: (d, ctx) =>
                ctx.isJimukyoku && d.sibuCode === HONKAI_SIBU_CODE && d.sibuUserSosa === CODE_SOSA_KANO
                    ? [['WLP029-0010']]
                    : []
        },
        {
            no: 20, // 【要確認 C-5・D-46】
            refs: ['sibuCode'],
            run: (d, ctx) => (ctx.isSibuUser && d.sibuCode !== ctx.sibuCode ? [['WLP029-0025']] : [])
        }
    ],
    [FILE_KEY.MEISAI]: [
        {
            no: 31,
            refs: ['bosyuNinzu'],
            run: (d, ctx, L) => (Number(d.bosyuNinzu) <= 0 ? [['WLP029-0016', L.bosyuNinzu, '1']] : [])
        },
        {
            no: 32,
            refs: ['kaisiJikoku', 'syuryoJikoku'],
            run: (d) =>
                !isEmpty(d.kaisiJikoku) && !isEmpty(d.syuryoJikoku) && d.kaisiJikoku > d.syuryoJikoku
                    ? [['SYSTEM-5104', '時間']]
                    : []
        },
        {
            no: 33,
            refs: ['nendo', 'jisiNengapi'],
            run: (d, ctx, L) => (inNendo(d.nendo, d.jisiNengapi) ? [] : [['SYSTEM-5104', L.jisiNengapi]])
        }
    ],
    [FILE_KEY.OUBO]: [
        {
            no: 37,
            refs: ['tel'],
            run: (d, ctx, L) => (!isEmpty(d.tel) && !TEL_PATTERN.test(d.tel) ? [['SYSTEM-5102', L.tel, '電話番号']] : [])
        },
        {
            no: 37,
            refs: ['fax'],
            run: (d, ctx, L) => (!isEmpty(d.fax) && !TEL_PATTERN.test(d.fax) ? [['SYSTEM-5102', L.fax, 'FAX番号']] : [])
        }
    ],
    [FILE_KEY.OUBO_MEISAI]: [
        {
            no: 48,
            refs: ['nendo', 'jujiKanoBi'],
            run: (d, ctx, L) => (inNendo(d.nendo, d.jujiKanoBi) ? [] : [['SYSTEM-5104', L.jujiKanoBi]])
        }
    ],
    [FILE_KEY.WARIATE]: [
        {
            no: 55,
            refs: ['wariFlag', 'kakuteiFlag'],
            run: (d, ctx, L) =>
                (d.wariFlag || FLAG_OFF) === (d.kakuteiFlag || FLAG_OFF)
                    ? [['WLP029-0026', L.wariFlag, L.kakuteiFlag, FLAG_ON]]
                    : []
        },
        {
            no: 56,
            refs: ['nendo', 'jujiNengapi'],
            run: (d, ctx, L) => (inNendo(d.nendo, d.jujiNengapi) ? [] : [['SYSTEM-5104', L.jujiNengapi]])
        }
    ],
    [FILE_KEY.JISSEKI]: [
        {
            no: 67, // 【要確認 D-22】
            refs: ['zeirisiKubun'],
            run: (d, ctx, L, bad) => {
                const rules = ZEIRISI_RULES[ZEIRISI_GROUPS[d.zeirisiKubun]];
                const result = [];
                Object.entries(rules).forEach(([name, rule]) => {
                    if (bad.has(name)) {
                        return;
                    }
                    if (rule === NG && !isEmpty(d[name])) {
                        result.push(['WLP029-0020', L[name]]);
                    } else if (rule === REQ && isEmpty(d[name])) {
                        result.push(['SYSTEM-5101', L[name]]);
                    }
                });
                return result;
            }
        },
        {
            no: 68,
            refs: [],
            run: (d, ctx, L, bad) =>
                JISSEKI_AMOUNTS.filter((name) => !bad.has(name) && toNumber(d[name]) < 0).map((name) => [
                    'WLP029-0016',
                    L[name],
                    '0'
                ])
        },
        {
            no: 69, // 【要確認 D-28】
            refs: ['zeirisiKubun', 'syakinGensen'],
            run: (d, ctx, L) =>
                !GENSEN_KUBUN.has(d.zeirisiKubun) && !isZeroOrEmpty(d.syakinGensen)
                    ? [['SYSTEM-5108', L.syakinGensen, '0または空']]
                    : []
        },
        {
            no: 70,
            refs: ['syakinHoho', 'kotuhiHoho'],
            run: (d, ctx, L) => {
                if (d.syakinHoho !== CODE_FURIKOMI_KOJIN && d.kotuhiHoho !== CODE_FURIKOMI_KOJIN) {
                    return [];
                }
                return FURIKOMI_ITEMS.filter((name) => isEmpty(d[name])).map((name) => ['SYSTEM-5101', L[name]]);
            }
        },
        {
            no: 71, // 【要確認 D-33】
            refs: ['kotuhiHoho', 'tyosyoKotuhi'],
            run: (d, ctx, L) =>
                d.kotuhiHoho === CODE_NASI && !isEmpty(d.tyosyoKotuhi) ? [['SYSTEM-5108', L.tyosyoKotuhi, '空']] : []
        },
        {
            no: 72, // 【要確認 D-38】
            refs: [],
            run: (d, ctx, L) => SIHARAI_ITEMS.filter((name) => !isEmpty(d[name])).map((name) => ['WLP029-0020', L[name]])
        },
        {
            no: 73,
            refs: ['furikomigaku'],
            run: (d, ctx, L, bad) => {
                let amount;
                if (!isEmpty(d.furikomigaku)) {
                    amount = Number(d.furikomigaku);
                } else {
                    // 空の場合は 謝金額－謝金源泉税額＋交通費額－交通費源泉税額＋調整金額
                    const items = ['syakingaku', 'syakinGensen', 'kotuhigaku', 'kotuhiGensen', 'tyoseiKingaku'];
                    if (items.some((name) => bad.has(name))) {
                        return [];
                    }
                    amount =
                        toNumber(d.syakingaku) -
                        toNumber(d.syakinGensen) +
                        toNumber(d.kotuhigaku) -
                        toNumber(d.kotuhiGensen) +
                        toNumber(d.tyoseiKingaku);
                }
                return amount < 0 ? [['WLP029-0016', L.furikomigaku, '0']] : [];
            }
        },
        {
            no: 74,
            refs: ['nendo', 'jujiNengapi'],
            run: (d, ctx, L) => (inNendo(d.nendo, d.jujiNengapi) ? [] : [['SYSTEM-5104', L.jujiNengapi]])
        }
    ]
};

// ---------- キー重複チェック（ファイル内） ----------
const KEY_NAMES = ['jigyoNo', 'basyoNo', 'nendo'];
const DUPLICATE_CHECKS = {
    [FILE_KEY.JIGYO]: { no: 19, keys: KEY_NAMES, id: 'WLP029-0003' },
    [FILE_KEY.MEISAI]: { no: 34, keys: [...KEY_NAMES, 'jisiNengapi'], id: 'WLP029-0004', x: '実施年月日' },
    [FILE_KEY.OUBO]: { no: 38, keys: [...KEY_NAMES, 'torokuNo'], id: 'WLP029-0004', x: '登録番号' },
    [FILE_KEY.OUBO_MEISAI]: {
        no: 49,
        keys: [...KEY_NAMES, 'torokuNo', 'jujiKanoBi'],
        id: 'WLP029-0005',
        x: '登録番号',
        y: '従事可能日'
    },
    [FILE_KEY.WARIATE]: {
        no: 57,
        keys: [...KEY_NAMES, 'jujiNengapi', 'torokuNo'],
        id: 'WLP029-0005',
        x: '従事年月日',
        y: '登録番号'
    },
    [FILE_KEY.JISSEKI]: {
        no: 75,
        keys: [...KEY_NAMES, 'jujiNengapi', 'torokuNo'],
        id: 'WLP029-0005',
        x: '従事年月日',
        y: '登録番号'
    }
};

/** 重複する行はすべてエラーとする。キー項目が単項目でエラーの行は対象外 */
function checkDuplicates(file, rows, errors) {
    const check = DUPLICATE_CHECKS[file.fileKey];
    const groups = new Map();
    rows.forEach((row) => {
        if (check.keys.some((name) => row.bad.has(name))) {
            return;
        }
        const key = JSON.stringify(check.keys.map((name) => row.data[name]));
        if (!groups.has(key)) {
            groups.set(key, []);
        }
        groups.get(key).push(row);
    });
    groups.forEach((sameRows) => {
        if (sameRows.length > 1) {
            sameRows.forEach((row) => {
                errors.push(createError(KUBUN.CATEGORY1, file, row.lineNo, check.no, check.id, check.x, check.y));
            });
        }
    });
}

// ---------- 本体 ----------
/**
 * ファイル内チェック
 * @param {Array} files 読み込んだファイル [{ fileKey, label, fileName, order, rows: [{ lineNo, values }] }]
 * @param {{userType: string, sibuCode: string}} user 取込ユーザ
 * @returns {{errors: Array, parsedFiles: Array}}
 *   parsedFiles：ファイルごとの行（項目名をキーにした値）。整合性チェック・事業単位の整理で使用する
 */
function checkCategory1(files, user) {
    const ctx = {
        isJimukyoku: user.userType === USER_TYPE.SUPER || user.userType === USER_TYPE.JIMUKYOKU,
        isSibuUser: user.userType === USER_TYPE.SIBUREN || user.userType === USER_TYPE.SIBU,
        sibuCode: user.sibuCode
    };
    const errors = [];
    const parsedFiles = [];

    files.forEach((file) => {
        const columns = LAYOUTS[file.fileKey];
        const labels = Object.fromEntries(columns.map((c) => [c.name, c.label]));
        // 支部ユーザの場合、支部ユーザ操作はチェックせず取り込まない（新レイアウト）
        const skipColumns = new Set(file.fileKey === FILE_KEY.JIGYO && ctx.isSibuUser ? ['sibuUserSosa'] : []);
        const rows = [];

        file.rows.forEach(({ lineNo, values }) => {
            // No.5 列数（その行の他のチェックは行わない）
            if (values.length !== columns.length) {
                errors.push(createError(KUBUN.CATEGORY1, file, lineNo, 5, 'SYSTEM-6104'));
                return;
            }
            const data = {};
            columns.forEach((column, i) => {
                data[column.name] = values[i];
            });

            // No.6～9 単項目
            const bad = new Set();
            columns.forEach((column) => {
                if (skipColumns.has(column.name)) {
                    return;
                }
                const error = checkItem(column, data[column.name]);
                if (error) {
                    bad.add(column.name);
                    errors.push(createError(KUBUN.CATEGORY1, file, lineNo, error.no, error.id, error.x, error.y));
                }
            });

            // 相関・範囲チェック
            (ROW_CHECKS[file.fileKey] || []).forEach((check) => {
                if (check.refs.some((name) => bad.has(name))) {
                    return;
                }
                check.run(data, ctx, labels, bad).forEach(([id, x, y, z]) => {
                    errors.push(createError(KUBUN.CATEGORY1, file, lineNo, check.no, id, x, y, z));
                });
            });

            rows.push({ lineNo, data, bad });
        });

        checkDuplicates(file, rows, errors);
        parsedFiles.push({
            fileKey: file.fileKey,
            label: file.label,
            fileName: file.fileName,
            order: file.order,
            rows: rows.map(({ lineNo, data }) => ({ lineNo, data }))
        });
    });

    return { errors, parsedFiles };
}

// ============================================================
// ② 事業単位の整理
// ============================================================
/**
 * 従事事業CSV登録 事業単位の整理（②）
 * ファイル内チェックが全件 OK の行を、事業キー（従事事業No＋従事場所No＋実施年度）ごとにまとめる。
 * 整合性チェック・登録は、この単位で行う。
 */

const FILE_KEYS = Object.values(FILE_KEY);

const jigyoKeyOf = (data) => [data.jigyoNo, data.basyoNo, data.nendo].join('|');

/**
 * @param {Array} parsedFiles checkCategory1 の parsedFiles
 * @returns {Array<{key: string, jigyoNo: string, basyoNo: string, nendo: string, files: object}>}
 *   files：登録対象ごとの行 [{ file, lineNo, data }]（file はエラー出力に使う対象ファイルの情報）
 */
function groupByJigyo(parsedFiles) {
    const groups = new Map();
    parsedFiles.forEach((parsed) => {
        const file = { fileKey: parsed.fileKey, label: parsed.label, fileName: parsed.fileName, order: parsed.order };
        parsed.rows.forEach(({ lineNo, data }) => {
            const key = jigyoKeyOf(data);
            if (!groups.has(key)) {
                const files = Object.fromEntries(FILE_KEYS.map((fileKey) => [fileKey, []]));
                groups.set(key, { key, jigyoNo: data.jigyoNo, basyoNo: data.basyoNo, nendo: data.nendo, files });
            }
            groups.get(key).files[parsed.fileKey].push({ file, lineNo, data });
        });
    });
    return [...groups.values()];
}

/** 整理結果をログに出力する（開発用） */
function outputGroupLog(groups) {
    // eslint-disable-next-line no-console
    console.log(`【事業単位の整理】事業数 ${groups.length} 件`);
    // eslint-disable-next-line no-console
    console.table(
        groups.map((g) => ({
            従事事業No: g.jigyoNo,
            従事場所No: g.basyoNo,
            実施年度: g.nendo,
            従事事業: g.files[FILE_KEY.JIGYO].length,
            明細: g.files[FILE_KEY.MEISAI].length,
            応募: g.files[FILE_KEY.OUBO].length,
            応募明細: g.files[FILE_KEY.OUBO_MEISAI].length,
            割当: g.files[FILE_KEY.WARIATE].length,
            実績: g.files[FILE_KEY.JISSEKI].length
        }))
    );
}

// ============================================================
// 整合性チェック
// ============================================================
/**
 * ③ 取込データ（LWC）と ④ 既存データ（Apex）で判定する（設計書「31」区分 2）。ファイル内チェックのエラーが 0 件の場合のみ行う。
 * ・③ LWC：取込データだけで判定できるもの。実装方式「LWC＋Apex」のチェックは、取込データで判定できない分の情報
 *   （有無・件数）を csvResult として Apex に渡す（「24」0-1）。
 * ・④ Apex：事業を CATEGORY2_BATCH_SIZE 件ずつに分け、順番に呼び出す（読み取りのみ）。
 * ・Apex のエラーは { fileKey, lineNo, checkNo, messageId, x, y, z } で受け取り、文言はこのファイルのメッセージで作る。
 */
const CATEGORY2_BATCH_SIZE = 50; // 1 回の Apex 呼出しの事業数【要確認 F-7】

/**
 * ③ 取込データでの判定【未実装】
 * @returns {{errors: Array, csvResults: object}} csvResults：事業キー → Apex に渡す取込データの判定結果
 */
function checkCategory2Lwc(groups) {
    const errors = [];
    const csvResults = {};
    groups.forEach((g) => {
        // TODO No.27・29・36・42～47・51・52・61～65・81～83 の取込データの部分
        csvResults[g.key] = {};
    });
    return { errors, csvResults };
}

/** Apex に渡すリクエスト（JSON 文字列）を CATEGORY2_BATCH_SIZE 事業ずつ作る */
function toCategory2Requests(groups, csvResults) {
    const jigyoList = groups.map((g) => ({
        key: g.key,
        jigyoNo: g.jigyoNo,
        basyoNo: g.basyoNo,
        nendo: g.nendo,
        rows: Object.values(FILE_KEY).flatMap((fileKey) =>
            g.files[fileKey].map((r) => ({ fileKey, lineNo: r.lineNo, data: r.data }))
        ),
        csvResult: csvResults[g.key]
    }));
    const requests = [];
    for (let i = 0; i < jigyoList.length; i += CATEGORY2_BATCH_SIZE) {
        requests.push(JSON.stringify({ jigyoList: jigyoList.slice(i, i + CATEGORY2_BATCH_SIZE) }));
    }
    return requests;
}

/** Apex のエラーを共通の形にする（null の置換値は空にする） */
function fromApexError(e, filesByKey) {
    return createError(
        KUBUN.CATEGORY2,
        filesByKey[e.fileKey],
        e.lineNo,
        e.checkNo,
        e.messageId,
        e.x ?? '',
        e.y ?? '',
        e.z ?? ''
    );
}

// ============================================================
// 画面（コンポーネント）
// ============================================================
const CSV_EXTENSION = /\.csv$/i;
const UNEXPECTED_ERROR = '予期しないエラーが発生しました。';

export default class JujJigyoCsvUploader extends LightningElement {
    // モーダルの表示状態を管理するフラグ（true: 表示, false: 非表示）
    @track isModalOpen = false;
    modalTitle = '';
    modalMessage = '';
    isLoading = false;
    // 画面上部のエラーメッセージ（ファイル単位のエラー）
    headerMessages = [];
    // 取込ユーザ（ユーザ種別・支部コード）【要確認 C-5】
    loginUser;
    // 選択したファイル（行の id → File）
    selectedFiles = {};
    // 行単位のエラー（ポップアップ・ダウンロード用。createErrorLog の戻り値）
    errorLog = null;
    isErrorModalOpen = false;

    @track rows = [
        { id: '1', fileKey: FILE_KEY.JIGYO, label: '従事事業ヘッダ', fileName: '', isChecked: false },
        { id: '2', fileKey: FILE_KEY.MEISAI, label: '従事事業明細', fileName: '', isChecked: false },
        { id: '3', fileKey: FILE_KEY.OUBO, label: '従事事業応募ヘッダ', fileName: '', isChecked: false },
        { id: '4', fileKey: FILE_KEY.OUBO_MEISAI, label: '従事事業応募明細', fileName: '', isChecked: false },
        { id: '5', fileKey: FILE_KEY.WARIATE, label: '従事事業割当', fileName: '', isChecked: false },
        { id: '6', fileKey: FILE_KEY.JISSEKI, label: '従事事業実績', fileName: '', isChecked: false }
    ];

    connectedCallback() {
        this.loadLoginUser();
    }

    async loadLoginUser() {
        try {
            this.loginUser = await getLoginUserInfo();
        } catch (error) {
            this.showHeaderMessages([error?.body?.message || UNEXPECTED_ERROR]);
        }
    }

    handleBrowseClick(event) {
        const rowId = event.target.dataset.id;
        const fileInput = this.template.querySelector(`input[data-fileid="${rowId}"]`);
        if (fileInput) {
            fileInput.click();
        }
    }

    handleFileChange(event) {
        const rowId = event.target.dataset.fileid;
        const file = event.target.files[0];

        if (file) {
            const rowIndex = this.rows.findIndex((row) => row.id === rowId);

            if (rowIndex !== -1) {
                // event.target.value を使用してブラウザが提供できる最大のパス情報（fakepath）を取得
                this.rows[rowIndex].fileName = event.target.value;
                this.selectedFiles[rowId] = file;
            }
        }
    }

    handleCheckboxChange(event) {
        const rowId = event.target.dataset.id;
        const checked = event.target.checked;
        const rowIndex = this.rows.findIndex((row) => row.id === rowId);

        if (rowIndex !== -1) {
            this.rows[rowIndex].isChecked = checked;
        }
    }

    handleClear() {
        this.rows = this.rows.map((row) => {
            return { ...row, fileName: '', isChecked: false };
        });
        this.selectedFiles = {};
        this.headerMessages = [];
        this.errorLog = null;

        const checkboxes = this.template.querySelectorAll('lightning-input[type="checkbox"]');
        checkboxes.forEach((checkbox) => {
            checkbox.checked = false;
        });

        const fileInputs = this.template.querySelectorAll('input[type="file"]');
        fileInputs.forEach((input) => {
            input.value = null;
        });
    }

    handleBack() {
        console.log('前の画面に戻ります');
    }

    // 登録ボタン：ファイル単位のチェック（No.1～3）の後、確認ダイアログを表示する
    handleRegisterClick() {
        this.headerMessages = [];
        this.errorLog = null;
        const errors = this.checkSelectedFiles();
        if (errors.length > 0) {
            this.showHeaderMessages(errors);
            return;
        }
        this.modalTitle = CONFIRM_REGISTER.title;
        this.modalMessage = CONFIRM_REGISTER.message;
        this.isModalOpen = true;
    }

    // 「登録」ボタン押下時にモーダルを表示する処理
    openModal() {
        this.isModalOpen = true;
    }

    // モーダル内の「キャンセル」や「×」アイコン押下時にモーダルを閉じる処理
    closeModal() {
        this.isModalOpen = false;
        this.buttonFlg = 0;
    }

    // モーダル内の「はい」：取込（チェック → 登録）
    async handleConfirmSave() {
        this.isModalOpen = false;
        this.isLoading = true;
        try {
            await this.runImport();
        } catch (error) {
            this.showHeaderMessages([error?.body?.message || error?.message || UNEXPECTED_ERROR]);
        } finally {
            this.isLoading = false;
        }
    }

    // ========== 取込 ==========

    // No.1 対象ファイル選択／No.2 ファイル必須選択／No.3 ファイル形式
    checkSelectedFiles() {
        const checkedRows = this.rows.filter((row) => row.isChecked);
        if (checkedRows.length === 0) {
            return [getMessage('WLP029-0001')];
        }
        const errors = [];
        checkedRows.forEach((row) => {
            const file = this.selectedFiles[row.id];
            if (!file) {
                errors.push(getMessage('WLP029-0002', row.label));
            } else if (!CSV_EXTENSION.test(file.name)) {
                errors.push(`${row.label}：${getMessage('SYSTEM-6102', 'CSV')}`);
            }
        });
        return errors;
    }

    async runImport() {
        if (!this.loginUser) {
            await this.loadLoginUser();
            if (!this.loginUser) {
                return;
            }
        }

        // ファイルの読込（No.4 データ存在・読込不可は画面に表示し、そのファイルのチェックは行わない）
        const checkedRows = this.rows.filter((row) => row.isChecked);
        const results = await Promise.all(checkedRows.map((row) => readCsv(this.selectedFiles[row.id])));
        const screenErrors = [];
        const files = [];
        checkedRows.forEach((row, i) => {
            const result = results[i];
            if (!result.ok) {
                screenErrors.push(`${row.label}：${getMessage('SYSTEM-6104')}`);
            } else if (result.rows.length === 0) {
                screenErrors.push(`${row.label}：${getMessage('SYSTEM-6103')}`);
            } else {
                files.push({
                    fileKey: row.fileKey,
                    label: row.label,
                    fileName: this.selectedFiles[row.id].name,
                    order: Number(row.id),
                    rows: result.rows
                });
            }
        });

        // ファイル内チェック（行単位のエラーはログに出力する）
        let parsedFiles = [];
        const checkResults = [];
        if (files.length > 0) {
            const category1 = checkCategory1(files, this.loginUser);
            outputLog(KUBUN.CATEGORY1, category1.errors);
            checkResults.push({ kubun: KUBUN.CATEGORY1, errors: category1.errors });
            if (category1.errors.length > 0) {
                screenErrors.push(getMessage('SYSTEM-6105'));
                this.showErrorLog(checkResults);
            }
            parsedFiles = category1.parsedFiles;
        }
        if (screenErrors.length > 0) {
            this.showHeaderMessages(screenErrors);
            return;
        }

        // ② 事業単位の整理
        const groups = groupByJigyo(parsedFiles);
        outputGroupLog(groups);

        // ③④ 整合性チェック（行単位のエラーはログに出力する）
        const category2Errors = await this.runCategory2(groups, parsedFiles);
        outputLog(KUBUN.CATEGORY2, category2Errors);
        checkResults.push({ kubun: KUBUN.CATEGORY2, errors: category2Errors });
        if (category2Errors.length > 0) {
            this.showHeaderMessages([getMessage('SYSTEM-6105')]);
            this.showErrorLog(checkResults);
            return;
        }

        // TODO 事業単位の登録
    }

    async runCategory2(groups, parsedFiles) {
        const filesByKey = Object.fromEntries(parsedFiles.map((f) => [f.fileKey, f]));
        const lwc = checkCategory2Lwc(groups);
        const errors = [...lwc.errors];
        // 5 秒を超える同期リクエストは組織全体で同時 10 件までのため、並列にせず順番に呼び出す【要確認 F-7】
        for (const requestJson of toCategory2Requests(groups, lwc.csvResults)) {
            // eslint-disable-next-line no-await-in-loop
            const result = await checkCategory2({ requestJson });
            errors.push(...(result.errors || []).map((e) => fromApexError(e, filesByKey)));
        }
        return errors;
    }

    // ========== メッセージ ==========

    showHeaderMessages(messages) {
        this.headerMessages = [...new Set(messages)]; // 同一文言は 1 件（html の key の重複防止）
    }

    get hasHeaderMessages() {
        return this.headerMessages.length > 0;
    }

    // ========== エラーログのポップアップ ==========

    // チェック終了時に自動で表示する（閉じた後は画面の「エラー内容を表示」から再表示できる）
    showErrorLog(results) {
        this.errorLog = createErrorLog(results);
        this.isErrorModalOpen = true;
    }

    get hasErrorLog() {
        return this.errorLog !== null;
    }

    get errorModalMessage() {
        return `${KUBUN_NAMES[this.errorLog.kubun]}でエラーが ${this.errorLog.total} 件見つかりました。`;
    }

    // ファイル内チェックでエラーの場合、整合性チェックは行っていないことを示す
    get showCategory2Note() {
        return this.errorLog.kubun === KUBUN.CATEGORY1;
    }

    openErrorModal() {
        this.isErrorModalOpen = true;
    }

    closeErrorModal() {
        this.isErrorModalOpen = false;
    }

    handleDownloadErrorLog() {
        downloadText(this.errorLog.fileName, this.errorLog.text);
        this.isErrorModalOpen = false;
    }
}
