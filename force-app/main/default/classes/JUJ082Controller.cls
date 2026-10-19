/**
 * JUJ082 応募情報検索 コントローラ
 * 設計書：JUJ082 応募情報検索 検索処理 v7
 *
 * ※ オブジェクト名・項目名は論理名で記載している（API 名確定後に一括置換する）。
 * ※ 従事事業応募は従事事業の主従子オブジェクトのため、参照範囲は従事事業に従う。
 *   SOQL はすべてユーザモードで実行し、支部の条件は付けない。
 * ※ LWC から呼び出すメソッドは内部クラスを引数・戻り値に使用できないため、
 *   引数は基本型または JSON 文字列、戻り値は基本型または Map／List<Map> とする。
 */
public with sharing class JUJ082Controller {

    // ==================== 定数 ====================
    // 名称取得の種別（getName の nameType）
    @TestVisible
    private static final String NAME_TOROKU = 'TOROKU'; // 登録番号 → 会員氏名
    @TestVisible
    private static final String NAME_SHIBU = 'SHIBU'; // 支部コード → 支部名
    @TestVisible
    private static final String NAME_SODANIN = 'SODANIN'; // 相談員番号 → 相談員氏名

    // 登録日時の表示形式（ユーザのタイムゾーンで表示）
    private static final String DATETIME_FORMAT = 'yyyy/MM/dd HH:mm:ss';

    // 【要確認 QA-20】メッセージ（{メッセージID, 文言}）
    @TestVisible
    private static final List<String> E_RANGE = new List<String>{ 'SYSTEM-5104', '範囲指定が正しくありません。' };

    // ==================== 初期表示：実施年度の初期値 ====================
    // 戻り値：汎用マスタの対象年度（取得できない場合は null）
    @AuraEnabled
    public static String getDefaultNendo() {
        // 【要確認】汎用マスタの抽出条件（対象年度を保持するレコードの特定方法）
        List<Hanyou_Master__c> recs = [
            SELECT 対象年度__c
            FROM Hanyou_Master__c
            WHERE 対象年度__c != null
            WITH USER_MODE
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0].対象年度__c;
    }

    // ==================== 従事事業キー変更時：事業の取得 ====================
    // 戻り値：{ basyoName, jigyo: { jigyoName, shibuCode, shibuName } | null }
    @AuraEnabled
    public static Map<String, Object> getJigyo(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        JigyoResult result = new JigyoResult();
        // 従事場所No が入力されている場合、従事場所名を取得する
        if (String.isNotBlank(jujiBasyoNo)) {
            List<従事場所マスタ__c> basyos = [
                SELECT 従事場所名__c
                FROM 従事場所マスタ__c
                WHERE 従事場所No__c = :jujiBasyoNo
                WITH USER_MODE
                LIMIT 1
            ];
            result.basyoName = basyos.isEmpty() ? null : basyos[0].従事場所名__c;
        }
        // 3項目すべて入力されている場合、従事事業を取得する
        従事事業__c jigyo = selectJigyo(jujiJigyoNo, jujiBasyoNo, jisiNendo);
        if (jigyo != null) {
            JigyoInfo info = new JigyoInfo();
            info.jigyoName = jigyo.従事事業名__c;
            info.shibuCode = jigyo.支部__r?.支部コード__c;
            info.shibuName = jigyo.支部__r?.Name;
            result.jigyo = info;
        }
        return toMap(result);
    }

    // ==================== 番号変更時：名称の取得 ====================
    // 引数：nameType（TOROKU／SHIBU／SODANIN）、code（入力された番号）
    // 戻り値：名称（未入力・取得できない場合は null。エラーとしない）
    @AuraEnabled
    public static String getName(String nameType, String code) {
        if (String.isBlank(code)) {
            return null;
        }
        if (nameType == NAME_TOROKU) {
            List<Contact> recs = [
                SELECT Name FROM Contact WHERE 登録番号__c = :code WITH USER_MODE LIMIT 1
            ];
            return recs.isEmpty() ? null : recs[0].Name;
        }
        if (nameType == NAME_SHIBU) {
            // 支部名は事務所・法人の名称（Name）とする（1つの支部コードに対応する支部は1件の想定。念のため先頭1件とする）
            List<Account> recs = [
                SELECT Name FROM Account
                WHERE 支部コード__c = :code
                WITH USER_MODE
                LIMIT 1
            ];
            return recs.isEmpty() ? null : recs[0].Name;
        }
        if (nameType == NAME_SODANIN) {
            List<相談員__c> recs = [
                SELECT 氏名__c FROM 相談員__c WHERE 相談員番号__c = :code WITH USER_MODE LIMIT 1
            ];
            return recs.isEmpty() ? null : recs[0].氏名__c;
        }
        return null;
    }

    // ==================== 1. 検索ボタン押下時 ====================
    // 引数：SearchCondition の JSON 文字列
    // 戻り値：検索結果の行リスト（各行は SearchRow のキーを持つ Map）
    @AuraEnabled
    public static List<Map<String, Object>> search(String conditionJson) {
        try {
            SearchCondition cond = (SearchCondition) JSON.deserialize(conditionJson, SearchCondition.class);

            // (1) 入力チェック：From ＞ To の場合はエラー（画面でもチェック済み。サーバ側は防御用）
            validateRanges(cond);

            // (2) 従事事業の取得。取得できない場合は 0件（エラーとしない）
            従事事業__c jigyo = selectJigyo(cond.jujiJigyoNo, cond.jujiBasyoNo, cond.jisiNendo);
            if (jigyo == null) {
                return new List<Map<String, Object>>();
            }

            // (3)〜(7) 抽出・ソート
            List<従事事業応募__c> apps = selectApplications(jigyo.Id, cond);
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (従事事業応募__c app : apps) {
                rows.add(toMap(toRow(app)));
            }
            return rows;
        } catch (JujiOboException e) {
            AuraHandledException ae = new AuraHandledException(e.getMessage());
            ae.setMessage(e.getMessage());
            throw ae;
        }
    }

    // ==================== (1) 入力チェック ====================
    private static void validateRanges(SearchCondition cond) {
        // 受付番号は数値として比較する
        if (cond.uketukeNoFrom != null && cond.uketukeNoTo != null && cond.uketukeNoFrom > cond.uketukeNoTo) {
            throw error(E_RANGE);
        }
        // 登録番号・支部コード・相談員番号は文字列として比較する
        if (isReversed(cond.torokuNoFrom, cond.torokuNoTo)
            || isReversed(cond.shibuCodeFrom, cond.shibuCodeTo)
            || isReversed(cond.sodaninNoFrom, cond.sodaninNoTo)) {
            throw error(E_RANGE);
        }
    }

    private static Boolean isReversed(String fromValue, String toValue) {
        return String.isNotBlank(fromValue) && String.isNotBlank(toValue) && fromValue.compareTo(toValue) > 0;
    }

    // ==================== Selector ====================
    // 従事事業（3項目のいずれかが未入力の場合はクエリを発行しない）
    private static 従事事業__c selectJigyo(String jigyoNo, String basyoNo, String nendo) {
        if (String.isBlank(jigyoNo) || String.isBlank(basyoNo) || String.isBlank(nendo)) {
            return null;
        }
        List<従事事業__c> recs = [
            SELECT Id, 従事事業名__c, 支部__r.支部コード__c, 支部__r.Name
            FROM 従事事業__c
            WHERE 従事事業No__c = :jigyoNo
            AND 従事場所__r.従事場所No__c = :basyoNo
            AND 実施年度__c = :nendo
            WITH USER_MODE
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }

    // (3)〜(7) 従事事業応募の抽出
    private static List<従事事業応募__c> selectApplications(Id jigyoId, SearchCondition cond) {
        Map<String, Object> binds = new Map<String, Object>{ 'jigyoId' => jigyoId };
        List<String> wheres = new List<String>();

        // ② 従事事業キー抽出条件（固定）
        wheres.add('従事事業__c = :jigyoId');

        // ③ 共通抽出条件（入力時のみ）
        if (cond.uketukeNoFrom != null) {
            wheres.add('受付番号__c >= :uketukeNoFrom');
            binds.put('uketukeNoFrom', cond.uketukeNoFrom);
        }
        if (cond.uketukeNoTo != null) {
            wheres.add('受付番号__c <= :uketukeNoTo');
            binds.put('uketukeNoTo', cond.uketukeNoTo);
        }

        // 氏名（会員・相談員共通の部分一致。「%」「_」は通常の文字として扱う）
        String namePattern = String.isBlank(cond.name) ? null : '%' + escapeLike(cond.name) + '%';
        if (namePattern != null) {
            binds.put('namePattern', namePattern);
        }

        // ④ 会員抽出条件
        List<String> memberConds = new List<String>{ '会員__c != null' };
        addRange(memberConds, binds, '会員__r.登録番号__c', 'torokuNo', cond.torokuNoFrom, cond.torokuNoTo);
        addRange(memberConds, binds, '会員__r.事務所__r.支部コード__c', 'shibuCode', cond.shibuCodeFrom, cond.shibuCodeTo);
        if (namePattern != null) {
            // 会員（取引先責任者）の氏名は Name に格納されている
            memberConds.add('会員__r.Name LIKE :namePattern');
        }

        // ⑤ 相談員抽出条件
        List<String> sodaninConds = new List<String>{ '相談員__c != null' };
        addRange(sodaninConds, binds, '相談員__r.相談員番号__c', 'sodaninNo', cond.sodaninNoFrom, cond.sodaninNoTo);
        if (namePattern != null) {
            sodaninConds.add('相談員__r.氏名__c LIKE :namePattern');
        }

        // (3) 検索対象判定・⑥ 抽出条件の結合
        Boolean memberSide = isEntered(cond.torokuNoFrom, cond.torokuNoTo)
            || isEntered(cond.shibuCodeFrom, cond.shibuCodeTo);
        Boolean sodaninSide = isEntered(cond.sodaninNoFrom, cond.sodaninNoTo);
        String memberWhere = '(' + String.join(memberConds, ' AND ') + ')';
        String sodaninWhere = '(' + String.join(sodaninConds, ' AND ') + ')';
        if (memberSide && !sodaninSide) {
            wheres.add(memberWhere); // a. 会員のみ
        } else if (sodaninSide && !memberSide) {
            wheres.add(sodaninWhere); // b. 相談員のみ
        } else {
            wheres.add('(' + memberWhere + ' OR ' + sodaninWhere + ')'); // c. 両方
        }

        // (5) 取得項目・(6) ソート順・(7) 取得件数（上限なし）
        String soql =
            'SELECT Id, 受付番号__c, CreatedDate, 会員__c, 会員__r.登録番号__c, 会員__r.Name,' +
            ' 相談員__c, 相談員__r.相談員番号__c, 相談員__r.氏名__c' +
            ' FROM 従事事業応募__c' +
            ' WHERE ' + String.join(wheres, ' AND ') +
            // 【要確認】ソート順一覧（未提供）。暫定：受付番号の昇順（画面で列ごとに並替え可）
            ' ORDER BY 受付番号__c ASC NULLS LAST, Id ASC';
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    // 範囲条件を追加する（入力されている側のみ）
    private static void addRange(
        List<String> conds, Map<String, Object> binds, String field, String bindName, String fromValue, String toValue
    ) {
        if (String.isNotBlank(fromValue)) {
            conds.add(field + ' >= :' + bindName + 'From');
            binds.put(bindName + 'From', fromValue);
        }
        if (String.isNotBlank(toValue)) {
            conds.add(field + ' <= :' + bindName + 'To');
            binds.put(bindName + 'To', toValue);
        }
    }

    private static Boolean isEntered(String fromValue, String toValue) {
        return String.isNotBlank(fromValue) || String.isNotBlank(toValue);
    }

    // LIKE の特殊文字（\ % _）をエスケープする
    @TestVisible
    private static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    // ==================== 変換 ====================
    // (5) 取得項目：受付番号・登録番号・相談員番号・氏名・登録日時
    // ※ 従事事業No・従事事業名・従事場所No・従事場所名・実施年度は画面の値を設定する（現行同様）
    private static SearchRow toRow(従事事業応募__c app) {
        SearchRow row = new SearchRow();
        row.applicationId = app.Id;
        row.uketukeNo = app.受付番号__c;
        row.createdDate = app.CreatedDate?.format(DATETIME_FORMAT);
        if (app.会員__c != null) {
            row.torokuNo = app.会員__r.登録番号__c;
            row.name = app.会員__r.Name;
        } else {
            row.sodaninNo = app.相談員__r?.相談員番号__c;
            row.name = app.相談員__r?.氏名__c;
        }
        return row;
    }

    private static Map<String, Object> toMap(Object dto) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dto));
    }

    // ==================== 例外 ====================
    public class JujiOboException extends Exception {
        public String messageId;
    }

    private static JujiOboException error(List<String> msg) {
        JujiOboException e = new JujiOboException(msg[1]);
        e.messageId = msg[0];
        return e;
    }

    // ==================== DTO（クラス内部でのみ使用） ====================
    // 事業の取得結果
    public class JigyoResult {
        public String basyoName;
        public JigyoInfo jigyo;
    }

    public class JigyoInfo {
        public String jigyoName;
        public String shibuCode;
        public String shibuName;
    }

    // 検索条件
    public class SearchCondition {
        public String jujiJigyoNo;
        public String jujiBasyoNo;
        public String jisiNendo;
        public Decimal uketukeNoFrom;
        public Decimal uketukeNoTo;
        public String torokuNoFrom;
        public String torokuNoTo;
        public String shibuCodeFrom;
        public String shibuCodeTo;
        public String sodaninNoFrom;
        public String sodaninNoTo;
        public String name;
    }

    // 検索結果の1行
    public class SearchRow {
        public Id applicationId;
        public Decimal uketukeNo;
        public String torokuNo; // 会員の場合のみ
        public String sodaninNo; // 相談員の場合のみ
        public String name;
        public String createdDate; // 登録日時（yyyy/MM/dd HH:mm:ss）
    }
}
