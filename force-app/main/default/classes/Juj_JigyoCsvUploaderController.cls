/**
 * 従事事業CSV登録（ファイル一括登録）コントローラ
 * ※ 第1類チェック（前提チェック）は LWC（juj_JigyoCsvUploader）で行う。
 *   本クラスは現在、画面の初期表示時に取込ユーザの情報を返すのみ。第2類チェック・事業単位の登録は後続で追加する。
 * ※ LWC との受け渡しは、戻り値を Map とする。
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
}
