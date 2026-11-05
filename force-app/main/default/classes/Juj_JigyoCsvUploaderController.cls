/**
 * 従事事業CSV登録（ファイル一括登録）コントローラ
 * ※ ファイル内チェックは LWC（juj_JigyoCsvUploader）で行う。
 * ※ 整合性チェックの既存データ分（④）は checkCategory2 で行う（読み取りのみ）。
 *   チェックの中身は未実装。現在は模擬として、全行に実際のメッセージでエラーを返す（SIMULATE_ERROR。ToBe 画面用）。
 * ※ 事業単位の登録は後続で追加する。
 * ※ LWC との受け渡しは、引数を JSON 文字列、戻り値を Map とする。
 */
public with sharing class Juj_JigyoCsvUploaderController {

    // ユーザ種別（LWC の USER_TYPE と同じ値）
    @TestVisible
    private static final String USER_TYPE_SUPER = 'SUPER'; // スーパーユーザ
    @TestVisible
    private static final String USER_TYPE_JIMUKYOKU = 'JIMUKYOKU'; // 事務局
    @TestVisible
    private static final String USER_TYPE_SIBUREN = 'SIBUREN'; // 支部連
    @TestVisible
    private static final String USER_TYPE_SIBU = 'SIBU'; // 支部

    // 【要確認 C-5】ユーザ種別・支部コードの取得方法が未確定のため、仮の値を返す
    @TestVisible
    private static final String TEMP_USER_TYPE = USER_TYPE_JIMUKYOKU;
    @TestVisible
    private static final String TEMP_SIBU_CODE = '000';

    /**
     * 取込ユーザの情報
     * @return userType：ユーザ種別（SUPER／JIMUKYOKU／SIBUREN／SIBU）、sibuCode：支部コード
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLoginUserInfo() {
        return new Map<String, Object>{
            'userType' => TEMP_USER_TYPE,
            'sibuCode' => TEMP_SIBU_CODE
        };
    }

    // ============================================================
    // 整合性チェック
    // ============================================================

    // 【模擬】true の間は、チェックの代わりに必ずエラーを返す（ToBe 画面用）
    //   取込データの全行に、そのファイルの整合性チェックのエラーを 1 行 2 件ずつ返す（行番号で SIMULATE_PATTERNS を順に使う）
    @TestVisible
    private static final Boolean SIMULATE_ERROR = true;
    @TestVisible
    private static final Integer SIMULATE_ERRORS_PER_ROW = 2;

    // ファイルの種類（LWC の FILE_KEY と同じ値）。並びは LWC のファイルの並びと同じ
    @TestVisible
    private static final List<String> FILE_KEYS = new List<String>{
        'jigyo', 'meisai', 'oubo', 'ouboMeisai', 'wariate', 'jisseki'
    };

    /**
     * 整合性チェック（④ 既存データとの関連チェック）
     * LWC が事業を一定件数ずつに分けて呼び出す。DB は読み取りのみ。
     * @param requestJson CheckRequest の JSON
     * @return errors：List<CheckError>（0 件ならエラーなし）
     */
    @AuraEnabled
    public static Map<String, Object> checkCategory2(String requestJson) {
        CheckRequest request = (CheckRequest) JSON.deserialize(requestJson, CheckRequest.class);
        List<CheckError> errors = new List<CheckError>();
        if (request.jigyoList == null) {
            return new Map<String, Object>{ 'errors' => errors };
        }

        if (SIMULATE_ERROR) {
            for (JigyoData jigyo : request.jigyoList) {
                errors.addAll(simulateErrors(jigyo));
            }
            return new Map<String, Object>{ 'errors' => errors };
        }

        // TODO ④ 既存データのチェック（設計書「31」区分 2・実装方式 Apex／LWC＋Apex）
        //   1. 全事業の事業キー・会員番号などをまとめ、オブジェクトごとに 1 回ずつ SOQL で取得する
        //   2. 事業ごとに、取込データ（rows）・csvResult と既存データを突き合わせる
        return new Map<String, Object>{ 'errors' => errors };
    }

    /** 【模擬】取込データの全行にエラーを作る（同じ行番号なら同じエラー） */
    private static List<CheckError> simulateErrors(JigyoData jigyo) {
        List<CheckError> errors = new List<CheckError>();
        for (RowData row : jigyo.rows == null ? new List<RowData>() : jigyo.rows) {
            List<CheckError> patterns = SIMULATE_PATTERNS.get(row.fileKey);
            if (patterns == null || patterns.isEmpty()) {
                continue;
            }
            Integer start = Math.max(row.lineNo - 2, 0) * SIMULATE_ERRORS_PER_ROW;
            for (Integer i = 0; i < SIMULATE_ERRORS_PER_ROW; i++) {
                CheckError p = patterns[Math.mod(start + i, patterns.size())];
                errors.add(new CheckError(row.fileKey, row.lineNo, p.checkNo, p.messageId, p.x, p.y, p.z));
            }
        }
        return errors;
    }

    /** 【模擬】ファイルごとの整合性チェックのエラー（設計書「31」の No.・メッセージ。行番号・ファイルは simulateErrors で設定） */
    @TestVisible
    private static final Map<String, List<CheckError>> SIMULATE_PATTERNS = new Map<String, List<CheckError>>{
        'jigyo' => new List<CheckError>{
            sim(22, 'WLP029-0013', '従事場所No', null),
            sim(23, 'WLP029-0009', '支部コード', '従事場所Noの支部コード'),
            sim(24, 'WLP029-0006', null, null),
            sim(21, 'WLP029-0014', '支部コード', null),
            sim(25, 'WLP029-0024', '2026年11月05日 10:30', null)
        },
        'meisai' => new List<CheckError>{
            sim(29, 'SYSTEM-7002', '従事事業', null),
            sim(35, 'WLP029-0007', '実施年月日', null),
            sim(36, 'WLP029-0017', null, null),
            sim(27, 'WLP029-0028', null, null),
            sim(28, 'WLP029-0013', '従事場所No', null),
            sim(26, 'WLP029-0025', null, null)
        },
        'oubo' => new List<CheckError>{
            sim(39, 'SYSTEM-7001', '登録番号', null),
            sim(41, 'WLP029-0007', '登録番号', null),
            sim(40, 'WLP029-0029', null, null),
            sim(42, 'WLP029-0018', null, null),
            sim(43, 'SYSTEM-7002', '従事事業応募明細', null),
            sim(45, 'WLP029-0019', null, null),
            sim(47, 'WLP029-0020', 'スキル特記事項', null),
            sim(47, 'WLP029-0020', '相談科目', null)
        },
        'ouboMeisai' => new List<CheckError>{
            sim(51, 'SYSTEM-7002', '従事事業応募', null),
            sim(52, 'SYSTEM-7002', '従事可能日と同じ実施年月日の従事事業明細', null),
            sim(53, 'WLP029-0008', '登録番号', '従事可能日'),
            sim(54, 'WLP029-0021', '従事可能日の従事事業割当または従事事業実績', null),
            sim(50, 'SYSTEM-7001', '登録番号', null),
            sim(30, 'WLP029-0024', '2026年11月05日 10:30', null)
        },
        'wariate' => new List<CheckError>{
            sim(58, 'SYSTEM-7001', '登録番号', null),
            sim(59, 'WLP029-0030', null, null),
            sim(60, 'WLP029-0008', '従事年月日', '登録番号'),
            sim(61, 'SYSTEM-7002', '従事年月日と同じ実施年月日の従事事業明細', null),
            sim(62, 'WLP029-0021', '同じ従事年月日の他事業の従事事業割当', null),
            sim(64, 'WLP029-0017', null, null),
            sim(65, 'WLP029-0027', null, null),
            sim(63, 'WLP029-0022', '同じ従事年月日の他事業の従事事業実績', null)
        },
        'jisseki' => new List<CheckError>{
            sim(76, 'SYSTEM-7001', '登録番号', null),
            sim(80, 'WLP029-0008', '従事年月日', '登録番号'),
            sim(77, 'SYSTEM-7001', '親税理士番号', null),
            sim(78, 'SYSTEM-7001', '法人番号', null),
            sim(79, 'WLP029-0015', '謝金振込先銀行コード', null),
            sim(81, 'SYSTEM-7002', '従事年月日と同じ実施年月日の従事事業明細', null),
            sim(82, 'WLP029-0022', '同じ従事年月日の他事業の従事事業実績', null),
            sim(83, 'WLP029-0021', '同じ従事年月日の他事業の従事事業割当', null)
        }
    };

    private static CheckError sim(Integer checkNo, String messageId, String x, String y) {
        return new CheckError(null, null, checkNo, messageId, x, y, null);
    }

    // ============================================================
    // 受け渡しの形
    // ============================================================

    /** 整合性チェックのリクエスト */
    public class CheckRequest {
        public List<JigyoData> jigyoList;
    }

    /** 事業（事業キー＝従事事業No＋従事場所No＋実施年度）ごとの取込データ */
    public class JigyoData {
        public String key;
        public String jigyoNo; // 従事事業No
        public String basyoNo; // 従事場所No
        public String nendo; // 実施年度
        public List<RowData> rows; // 6 ファイルの行（ファイルの並び・行番号の順）
        public Map<String, String> csvResult; // ③ LWC で判定した、Apex で使う取込データの判定結果（有無・件数など）
    }

    /** 取込データの 1 行 */
    public class RowData {
        public String fileKey; // FILE_KEYS のいずれか
        public Integer lineNo; // CSV の行番号（ヘッダ行を 1 行目とする）
        public Map<String, String> data; // 項目名（LWC のレイアウトの name）→ CSV の値
    }

    /** チェックエラー（文言は LWC で messageId と x／y／z から作る） */
    public class CheckError {
        @AuraEnabled
        public String fileKey;
        @AuraEnabled
        public Integer lineNo;
        @AuraEnabled
        public Integer checkNo; // 設計書「31」のチェック No
        @AuraEnabled
        public String messageId;
        @AuraEnabled
        public String x;
        @AuraEnabled
        public String y;
        @AuraEnabled
        public String z;

        public CheckError(String fileKey, Integer lineNo, Integer checkNo, String messageId, String x, String y, String z) {
            this.fileKey = fileKey;
            this.lineNo = lineNo;
            this.checkNo = checkNo;
            this.messageId = messageId;
            this.x = x;
            this.y = y;
            this.z = z;
        }
    }
}
