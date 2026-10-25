/**
 * JUJ082 応募情報検索 コントローラ
 * 設計書：機能設計書 処理詳細（JUJ080／081／082 共通シート）
 *   コメント中の番号は「1.画面アクション No.」「4.入力チェック No.」「5.データ更新 (n)」に対応する。
 *
 * ※ 従事事業応募（Juji_Jigyo_Oubo__c）は従事事業を参照関係で参照する（2026/10/23 時点）。参照範囲は共有設定に従う。
 *   SOQL はすべてユーザモードで実行し、支部の条件は付けない。
 * ※ LWC から呼び出すメソッドは内部クラスを引数・戻り値に使用できないため、
 *   引数は基本型または JSON 文字列、戻り値は基本型または Map／List<Map> とする。
 */
public with sharing class Juj_OubojouhoukensakuModelController {

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

    // 4.入力チェック No.24〜27 相関（区間）チェックのメッセージ（{メッセージID, 文言}）。{0} は項目名【要確認 QA-20】ID は暫定
    @TestVisible
    private static final List<String> E_RANGE = new List<String>{
        'SYSTEM-5104',
        '{0}(From)は{0}(To)以下の値を入力してください。'
    };
    // 相関（区間）チェックの項目名（画面の既定ラベル）
    @TestVisible
    private static final String LABEL_UKETUKE_NO = '受付番号';
    @TestVisible
    private static final String LABEL_TOROKU_NO = '登録番号';
    @TestVisible
    private static final String LABEL_SHIBU_CODE = '支部コード';
    @TestVisible
    private static final String LABEL_SODANIN_NO = '相談員番号';

    // ==================== 画面アクション No.36 従事場所名・従事事業の取得 ====================
    // 戻り値：{ basyoName, jigyo: { jigyoName, shibuCode, shibuName } | null }
    @AuraEnabled
    public static Map<String, Object> getJigyo(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        JigyoResult result = new JigyoResult();
        // 従事場所No. が入力されている場合、従事場所名を取得する
        if (String.isNotBlank(jujiBasyoNo)) {
            List<Juji_Basyo_Master__c> basyos = [
                SELECT JujM_Juji_Basyo_Name__c
                FROM Juji_Basyo_Master__c
                WHERE JujM_Juji_Basyo_No__c = :jujiBasyoNo
                WITH USER_MODE
                LIMIT 1
            ];
            result.basyoName = basyos.isEmpty() ? null : basyos[0].JujM_Juji_Basyo_Name__c;
        }
        // 3項目すべて入力されている場合、従事事業を取得する（JUJ080 No.18 と同じ。最終受付番号・入力制御は行わない）
        Juji_Jigyo__c jigyo = selectJigyo(jujiJigyoNo, jujiBasyoNo, jisiNendo);
        if (jigyo != null) {
            JigyoInfo info = new JigyoInfo();
            info.jigyoName = jigyo.Juji_Juji_Jigyo_Name__c;
            info.shibuCode = jigyo.Juji_Jimusyo_Hojin__r?.Jims_Sibu_Code__c;
            info.shibuName = jigyo.Juji_Jimusyo_Hojin__r?.Jims_Sibu_Name__c;
            result.jigyo = info;
        }
        return toMap(result);
    }

    // ==================== 画面アクション No.39 名称の取得 ====================
    // 引数：nameType（TOROKU／SHIBU／SODANIN）、code（入力された番号）
    // 戻り値：名称（未入力・取得できない場合は null。エラーとしない）
    @AuraEnabled
    public static String getName(String nameType, String code) {
        if (String.isBlank(code)) {
            return null;
        }
        if (nameType == NAME_TOROKU) {
            // 登録番号：会員の氏名
            List<Contact> recs = [
                SELECT Name FROM Contact WHERE Kaii_Toroku_No__c = :code WITH USER_MODE LIMIT 1
            ];
            return recs.isEmpty() ? null : recs[0].Name;
        }
        if (nameType == NAME_SHIBU) {
            // 支部コード：事務所・法人の支部名（同じ支部コードの事務所・法人は支部名も同じため、先頭1件とする）
            List<Account> recs = [
                SELECT Jims_Sibu_Name__c FROM Account
                WHERE Jims_Sibu_Code__c = :code
                WITH USER_MODE
                LIMIT 1
            ];
            return recs.isEmpty() ? null : recs[0].Jims_Sibu_Name__c;
        }
        if (nameType == NAME_SODANIN) {
            // 相談員番号：相談員の氏名
            List<Soudanin_Master__c> recs = [
                SELECT SouM_Sodanin_Name__c FROM Soudanin_Master__c WHERE SouM_Sodanin_No__c = :code WITH USER_MODE LIMIT 1
            ];
            return recs.isEmpty() ? null : recs[0].SouM_Sodanin_Name__c;
        }
        return null;
    }

    // ==================== 画面アクション No.42 検索：5.データ更新 (7) ====================
    // 引数：SearchCondition の JSON 文字列
    // 戻り値：検索結果の行リスト（各行は SearchRow のキーを持つ Map）
    @AuraEnabled
    public static List<Map<String, Object>> search(String conditionJson) {
        try {
            SearchCondition cond = (SearchCondition) JSON.deserialize(conditionJson, SearchCondition.class);

            // 4.入力チェック No.24〜27：From ＞ To の場合はエラー（画面でチェック済み。サーバ側は防御用）
            validateRanges(cond);

            // ① 従事事業の取得。従事事業キーが未入力、または取得できない場合は 0件（エラーとしない）
            Juji_Jigyo__c jigyo = selectJigyo(cond.jujiJigyoNo, cond.jujiBasyoNo, cond.jisiNendo);
            if (jigyo == null) {
                return new List<Map<String, Object>>();
            }

            // ② 従事事業応募の取得（③ 検索対象判定を含む）
            // ソート順：受付番号の昇順。未採番（0・未設定）は末尾とする
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            List<Map<String, Object>> unnumberedRows = new List<Map<String, Object>>();
            for (Juji_Jigyo_Oubo__c app : selectApplications(jigyo.Id, cond)) {
                if (app.Oubo_Uketuke_No__c == null || app.Oubo_Uketuke_No__c == 0) {
                    unnumberedRows.add(toMap(toRow(app)));
                } else {
                    rows.add(toMap(toRow(app)));
                }
            }
            rows.addAll(unnumberedRows);
            return rows;
        } catch (JujiOboException e) {
            AuraHandledException ae = new AuraHandledException(e.getMessage());
            ae.setMessage(e.getMessage());
            throw ae;
        }
    }

    // ==================== 4.入力チェック No.24〜27 相関（区間）チェック ====================
    // ※ サーバのエラーは1件ずつ表示するため、最初にエラーとなった項目のみ返す
    private static void validateRanges(SearchCondition cond) {
        // No.24 受付番号は数値として比較する
        if (cond.uketukeNoFrom != null && cond.uketukeNoTo != null && cond.uketukeNoFrom > cond.uketukeNoTo) {
            throw rangeError(LABEL_UKETUKE_NO);
        }
        // No.25〜27 登録番号・支部コード・相談員番号は文字列として比較する
        if (isReversed(cond.torokuNoFrom, cond.torokuNoTo)) {
            throw rangeError(LABEL_TOROKU_NO);
        }
        if (isReversed(cond.shibuCodeFrom, cond.shibuCodeTo)) {
            throw rangeError(LABEL_SHIBU_CODE);
        }
        if (isReversed(cond.sodaninNoFrom, cond.sodaninNoTo)) {
            throw rangeError(LABEL_SODANIN_NO);
        }
    }

    private static Boolean isReversed(String fromValue, String toValue) {
        return String.isNotBlank(fromValue) && String.isNotBlank(toValue) && fromValue.compareTo(toValue) > 0;
    }

    // ==================== Selector ====================
    // 従事事業（3項目のいずれかが未入力の場合はクエリを発行しない）
    private static Juji_Jigyo__c selectJigyo(String jigyoNo, String basyoNo, String nendo) {
        if (String.isBlank(jigyoNo) || String.isBlank(basyoNo) || String.isBlank(nendo)) {
            return null;
        }
        List<Juji_Jigyo__c> recs = [
            SELECT Id, Juji_Juji_Jigyo_Name__c, Juji_Jimusyo_Hojin__r.Jims_Sibu_Code__c, Juji_Jimusyo_Hojin__r.Jims_Sibu_Name__c
            FROM Juji_Jigyo__c
            WHERE Juji_Juji_Jigyo_No__c = :jigyoNo
            AND Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_No__c = :basyoNo
            AND Juji_Jisi_Nendo__c = :nendo
            WITH USER_MODE
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }

    // 5.データ更新 (7)② 従事事業応募の取得
    private static List<Juji_Jigyo_Oubo__c> selectApplications(Id jigyoId, SearchCondition cond) {
        Map<String, Object> binds = new Map<String, Object>{ 'jigyoId' => jigyoId };
        List<String> wheres = new List<String>();

        // 従事事業（固定）
        wheres.add('Oubo_Juji_Jigyo__c = :jigyoId');

        // 受付番号（入力時のみ）
        if (cond.uketukeNoFrom != null) {
            wheres.add('Oubo_Uketuke_No__c >= :uketukeNoFrom');
            binds.put('uketukeNoFrom', cond.uketukeNoFrom);
        }
        if (cond.uketukeNoTo != null) {
            wheres.add('Oubo_Uketuke_No__c <= :uketukeNoTo');
            binds.put('uketukeNoTo', cond.uketukeNoTo);
        }

        // 氏名（会員・相談員共通の部分一致。「%」「_」は通常の文字として扱う）
        String namePattern = String.isBlank(cond.name) ? null : '%' + escapeLike(cond.name) + '%';
        if (namePattern != null) {
            binds.put('namePattern', namePattern);
        }

        // ［会員条件］
        List<String> memberConds = new List<String>{ 'Oubo_Kaiin__c != null' };
        addRange(memberConds, binds, 'Oubo_Kaiin__r.Kaii_Toroku_No__c', 'torokuNo', cond.torokuNoFrom, cond.torokuNoTo);
        addRange(memberConds, binds, 'Oubo_Kaiin__r.Account.Jims_Sibu_Code__c', 'shibuCode', cond.shibuCodeFrom, cond.shibuCodeTo);
        if (namePattern != null) {
            // 会員（Contact）の氏名は Name に格納されている
            memberConds.add('Oubo_Kaiin__r.Name LIKE :namePattern');
        }

        // ［相談員条件］
        List<String> sodaninConds = new List<String>{ 'Oubo_Soudanin_Master__c != null' };
        addRange(
            sodaninConds, binds, 'Oubo_Soudanin_Master__r.SouM_Sodanin_No__c', 'sodaninNo', cond.sodaninNoFrom, cond.sodaninNoTo
        );
        if (namePattern != null) {
            sodaninConds.add('Oubo_Soudanin_Master__r.SouM_Sodanin_Name__c LIKE :namePattern');
        }

        // ③ 検索対象判定：会員側（登録番号・支部コード）・相談員側（相談員番号）の入力状況で抽出条件を決める
        Boolean memberSide = isEntered(cond.torokuNoFrom, cond.torokuNoTo)
            || isEntered(cond.shibuCodeFrom, cond.shibuCodeTo);
        Boolean sodaninSide = isEntered(cond.sodaninNoFrom, cond.sodaninNoTo);
        String memberWhere = '(' + String.join(memberConds, ' AND ') + ')';
        String sodaninWhere = '(' + String.join(sodaninConds, ' AND ') + ')';
        if (memberSide && !sodaninSide) {
            wheres.add(memberWhere); // 会員側のみ入力：会員の応募のみ
        } else if (sodaninSide && !memberSide) {
            wheres.add(sodaninWhere); // 相談員側のみ入力：相談員の応募のみ
        } else {
            wheres.add('(' + memberWhere + ' OR ' + sodaninWhere + ')'); // 両方とも入力、または両方とも未入力：両方
        }

        // 取得件数の上限なし。並び順は受付番号の昇順（未採番の並べ替えは呼出し元で行う）
        String soql =
            'SELECT Id, Oubo_Uketuke_No__c, CreatedDate, Oubo_Kaiin__c, Oubo_Kaiin__r.Kaii_Toroku_No__c, Oubo_Kaiin__r.Name,' +
            ' Oubo_Soudanin_Master__c, Oubo_Soudanin_Master__r.SouM_Sodanin_No__c, Oubo_Soudanin_Master__r.SouM_Sodanin_Name__c' +
            ' FROM Juji_Jigyo_Oubo__c' +
            ' WHERE ' + String.join(wheres, ' AND ') +
            ' ORDER BY Oubo_Uketuke_No__c ASC NULLS LAST, Id ASC';
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
    // 5.データ更新 (7)② の設定先：受付番号・登録番号・相談員番号・氏名・登録日時
    // ※ 従事事業No.・従事事業名・従事場所No.・従事場所名・実施年度は画面の値を設定する（現行同様）
    private static SearchRow toRow(Juji_Jigyo_Oubo__c app) {
        SearchRow row = new SearchRow();
        row.applicationId = app.Id;
        row.uketukeNo = app.Oubo_Uketuke_No__c;
        row.createdDate = app.CreatedDate?.format(DATETIME_FORMAT);
        if (app.Oubo_Kaiin__c != null) {
            row.torokuNo = app.Oubo_Kaiin__r.Kaii_Toroku_No__c;
            row.name = app.Oubo_Kaiin__r.Name;
        } else {
            row.sodaninNo = app.Oubo_Soudanin_Master__r?.SouM_Sodanin_No__c;
            row.name = app.Oubo_Soudanin_Master__r?.SouM_Sodanin_Name__c;
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

    // 相関（区間）チェックのエラー（{0} を項目名に置き換える）
    private static JujiOboException rangeError(String label) {
        JujiOboException e = new JujiOboException(String.format(E_RANGE[1], new List<Object>{ label }));
        e.messageId = E_RANGE[0];
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
