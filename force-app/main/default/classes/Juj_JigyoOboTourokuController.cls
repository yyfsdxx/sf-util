/**
 * JUJ080 従事事業応募登録 コントローラ
 * 設計書：機能設計書 処理詳細（JUJ080／081／082 共通シート）
 *   コメント中の番号は「1.画面アクション No.」「4.入力チェック No.」「5.データ更新 (n)」に対応する。
 *
 * ※ 従事事業応募（Juji_Jigyo_Oubo__c）は従事事業を参照関係で参照する（2026/10/23 時点）。参照範囲は共有設定に従う。
 *   SOQL・DML はすべてユーザモードで実行し、支部の条件は付けない。
 * ※ 一括割当実行中チェック・排他チェックは共通（Juj_CommonController）を呼び出す。
 *   エラー時は共通側で AuraHandledException が発生し、そのまま画面へ返す（トランザクションはロールバックされる）。
 * ※ 業務エラーは JujiOboException で発生させ、各メソッドの入口で AuraHandledException に変換する。
 *   例外を画面へ返した時点でトランザクションはロールバックされる。
 * ※ LWC から呼び出すメソッドは、内部クラスを引数・戻り値に使用できないため、以下のとおりとする。
 *   ・引数：プリミティブ型（従事事業キーは3項目に分割、登録リクエストは JSON 文字列）
 *   ・戻り値：Map<String, Object>（内部クラスを JSON 経由で変換。キーは内部クラスの項目名）
 */
public with sharing class Juj_JigyoOboTourokuController {

    // ==================== 定数 ====================
    private static final String TYPE_MEMBER = 'MEMBER'; // 会員
    private static final String TYPE_SODANIN = 'SODANIN'; // 相談員

    // 従事可能曜日フラグの値
    @TestVisible
    private static final String WEEKDAY_KA = '可';
    @TestVisible
    private static final String WEEKDAY_FUKA = '不可';

    // 従事可能曜日（画面の値）→ 従事可能曜日フラグの項目
    @TestVisible
    private static final List<String> WEEKDAYS = new List<String>{ '日', '月', '火', '水', '木', '金', '土' };
    @TestVisible
    private static final Map<String, String> WEEKDAY_FIELDS = new Map<String, String>{
        '日' => 'Oubo_Juji_Kano_Yobi_Flag_Sun__c',
        '月' => 'Oubo_Juji_Kano_Yobi_Flag_Mon__c',
        '火' => 'Oubo_Juji_Kano_Yobi_Flag_Tue__c',
        '水' => 'Oubo_Juji_Kano_Yobi_Flag_Wed__c',
        '木' => 'Oubo_Juji_Kano_Yobi_Flag_Thu__c',
        '金' => 'Oubo_Juji_Kano_Yobi_Flag_Fri__c',
        '土' => 'Oubo_Juji_Kano_Yobi_Flag_Sat__c'
    };

    // スキル（8科目）の項目。画面とはこの項目名（API 名）をキーに受け渡す（並びは画面の表示順）
    @TestVisible
    private static final List<String> SKILL_FIELDS = new List<String>{
        'Oubo_Skill_Syotoku_Zei__c', // 所得税
        'Oubo_Skill_Kaisyaho__c', // 会社法
        'Oubo_Skill_Hojin_Zei__c', // 法人税
        'Oubo_Skill_Zaimu_Kaikei__c', // 財務会計
        'Oubo_Skill_Sisan_Zei__c', // 資産税
        'Oubo_Skill_Joto_Sanrin__c', // 譲渡山林
        'Oubo_Skill_Syohi_Zei__c', // 消費税
        'Oubo_Skill_Zoyo_Zei__c' // 贈与税
    };

    // メッセージ（{メッセージID, 文言}）。末尾は 4.入力チェックの No.【要確認 QA-20】ID は暫定
    @TestVisible
    private static final List<String> E_JIGYO_NOT_FOUND = new List<String>{ 'JUJ080-E001', '従事事業が存在しません。' }; // No.16
    @TestVisible
    private static final List<String> E_JUJISHA_NOT_FOUND = new List<String>{ 'WLP007-0009', '従事者が存在しません。' }; // No.17
    @TestVisible
    private static final List<String> E_NO_JISSHIBI = new List<String>{ 'JUJ080-E002', '実施日が登録されていません。' }; // No.14
    @TestVisible
    private static final List<String> E_ALREADY_EXISTS = new List<String>{
        'JUJ080-E003',
        '指定された従事者の応募情報はすでに登録されています。応募情報表示ボタンで登録内容を表示してください。'
    }; // No.18
    @TestVisible
    private static final List<String> E_UPDATE_NOT_FOUND = new List<String>{ 'JUJ080-E004', '更新するレコードが存在しません。' }; // No.19
    @TestVisible
    private static final List<String> E_APPLICATION_NOT_FOUND = new List<String>{ 'WLP007-0008', '指定された応募情報は登録されていません。' }; // No.21
    @TestVisible
    private static final List<String> E_ASSIGNED = new List<String>{ 'WLP007-0006', 'すでに割当されているため削除できません。' }; // No.22

    // 割当のフラグ項目（割当フラグ・確定フラグ）は選択リスト。値 '1' で ON（仮割当・確定）
    @TestVisible
    private static final String FLAG_ON = '1';

    // 事業の必須入力フラグ・任意入力フラグ（選択リスト）の値
    @TestVisible
    private static final String REQUIRED_ON = '必須'; // 必須入力フラグ：必須（ほかに「省略可」）
    @TestVisible
    private static final String OPTIONAL_OFF = '禁止'; // 任意入力フラグ：禁止（ほかに「許可」）

    // 応募の氏名（Oubo_Shimei__c）の桁数。超える場合は切り捨てて設定する
    private static final Integer SHIMEI_LENGTH = 32;

    // 共通チェックの引数
    private static final String OBO_OBJECT_NAME = 'Juji_Jigyo_Oubo__c'; // 排他チェック対象のオブジェクト API 名
    private static final Set<String> NO_CHECK_KEYS = new Set<String>(); // 一括割当チェックの checkKeys（現在は未使用のため空）

    // ==================== 画面アクション No.2・No.18 従事場所名・従事事業の取得 ====================
    // 戻り値：{ basyoName, jigyo: { jigyoName, shibuCode, shibuName, lastUketukeNo, inputControl } | null }
    @AuraEnabled
    public static Map<String, Object> getJigyo(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        JigyoKey jigyoKey = toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo);
        JigyoResult result = new JigyoResult();
        // No.2 従事場所No. が入力されている場合、従事場所名を取得する
        if (String.isNotBlank(jigyoKey.jujiBasyoNo)) {
            Juji_Basyo_Master__c basyo = selectBasyo(jigyoKey.jujiBasyoNo);
            result.basyoName = basyo == null ? null : basyo.JujM_Juji_Basyo_Name__c;
        }
        // No.18 3項目すべて入力されている場合、従事事業を取得する
        Juji_Jigyo__c jigyo = selectJigyo(jigyoKey, false);
        if (jigyo != null) {
            result.jigyo = toJigyoInfo(jigyo);
        }
        return toMap(result);
    }

    // ==================== 画面アクション No.19 従事者の取得 ====================
    // 戻り値：従事者情報部。取得できない場合は null（エラーとしない）
    @AuraEnabled
    public static Map<String, Object> getJujisha(String jujishaNo) {
        return toMap(findJujisha(jujishaNo));
    }

    // ==================== 画面アクション No.7・No.8（No.20）応募の読込：5.データ更新 (1) ====================
    // 応募情報表示ボタン（No.7）：従事事業キー＋登録番号/相談員番号で取得する（applicationId は指定しない）
    // 応募情報検索からの戻り（No.8）：applicationId で取得する
    // 戻り値：{ jigyoKey, jujishaNo, jujisha, application }（応募情報表示で応募がない場合は application = null → 追加モード）
    @AuraEnabled
    public static Map<String, Object> loadApplication(
        Id applicationId,
        String jujiJigyoNo,
        String jujiBasyoNo,
        String jisiNendo,
        String jujishaNo
    ) {
        try {
            LoadApplicationResult result = applicationId != null
                ? loadApplicationById(applicationId)
                : loadApplicationByJujisha(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), jujishaNo);
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // No.7 従事事業キー＋番号で応募を取得する
    private static LoadApplicationResult loadApplicationByJujisha(JigyoKey key, String jujishaNo) {
        // 従事事業の存在は画面でチェック済み（4.入力チェック No.5）。ここでは防御のため再チェックする
        Juji_Jigyo__c jigyo = selectJigyo(key, false);
        if (jigyo == null) {
            throw error(E_JIGYO_NOT_FOUND);
        }
        // 4.入力チェック No.17 会員・相談員のいずれからも取得できない場合はエラー
        JujishaInfo jujisha = findJujisha(jujishaNo);
        if (jujisha == null) {
            throw error(E_JUJISHA_NOT_FOUND);
        }
        // 5.データ更新 (1) 従事事業応募を取得する（取得できない場合は application = null → 追加モード）
        Juji_Jigyo_Oubo__c app = selectApplicationByJujisha(jigyo.Id, jujisha);
        LoadApplicationResult result = new LoadApplicationResult();
        result.jigyoKey = key;
        result.jujishaNo = jujishaNo;
        result.jujisha = jujisha;
        result.application = app == null ? null : toApplicationInfo(app);
        return result;
    }

    // No.8 応募IDで応募を取得する（応募の従事事業キー・番号も返す）
    private static LoadApplicationResult loadApplicationById(Id applicationId) {
        Juji_Jigyo_Oubo__c app = selectApplicationById(applicationId);
        // 4.入力チェック No.21 応募が存在しない場合はエラー
        if (app == null) {
            throw error(E_APPLICATION_NOT_FOUND);
        }
        LoadApplicationResult result = new LoadApplicationResult();
        result.jigyoKey = toKey(
            app.Oubo_Juji_Jigyo__r.Juji_Juji_Jigyo_No__c,
            app.Oubo_Juji_Jigyo__r.Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_No__c,
            app.Oubo_Juji_Jigyo__r.Juji_Jisi_Nendo__c
        );
        result.jujishaNo = app.Oubo_Kaiin__c != null
            ? app.Oubo_Kaiin__r.Kaii_Toroku_No__c
            : app.Oubo_Soudanin_Master__r.SouM_Sodanin_No__c;
        result.jujisha = findJujisha(result.jujishaNo);
        result.application = toApplicationInfo(app);
        return result;
    }

    // ==================== 画面アクション No.11・No.12 従事事業の状態チェック ====================
    // 従事可能日入力ボタン（No.11、checkJisshibi = true）：4.入力チェック No.14・No.15
    // 登録ボタン（No.12、checkJisshibi = false）：登録確認前に 4.入力チェック No.15（登録処理内でも再チェックする）
    @AuraEnabled
    public static void checkJigyo(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo, Boolean checkJisshibi) {
        try {
            // 従事事業の存在は画面でチェック済み（4.入力チェック No.5）。ここでは防御のため再チェックする
            Juji_Jigyo__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), false);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            // No.14 実施日が1件もない場合はエラー
            if (checkJisshibi == true && !hasJisshibi(jigyo.Id)) {
                throw error(E_NO_JISSHIBI);
            }
            // No.15 一括割当実行中の場合はエラー
            checkBulkAssigning(jigyo.Id);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 画面アクション No.12 登録：5.データ更新 (2) 追加モード・(3) 変更モード ====================
    // 引数：SaveRequest の JSON 文字列
    // 戻り値：{ uketukeNo }（採番しなかった場合は null）
    @AuraEnabled
    public static Map<String, Object> saveApplication(String requestJson) {
        try {
            SaveRequest request = (SaveRequest) JSON.deserialize(requestJson, SaveRequest.class);
            // 応募IDを保持していない場合は追加モード
            Boolean isAdd = request.applicationId == null;

            // ② 入力チェック（サーバ）
            // 従事事業をロック（FOR UPDATE）して取得する（No.16）。取得後、一括割当実行中を再チェックする（No.15）
            Juji_Jigyo__c jigyo = selectJigyo(request.jigyoKey, true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            checkBulkAssigning(jigyo.Id);
            // 従事者を取得する（No.17）
            JujishaInfo jujisha = findJujisha(request.jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }
            // 従事事業・従事者が一致する従事事業応募を取得する
            Juji_Jigyo_Oubo__c existing = selectApplicationByJujisha(jigyo.Id, jujisha);
            if (isAdd && existing != null) {
                throw error(E_ALREADY_EXISTS); // No.18 二重登録（追加モード）
            }
            if (!isAdd && existing == null) {
                throw error(E_UPDATE_NOT_FOUND); // No.19 更新対象データ未存在（変更モード）
            }
            if (!isAdd) {
                checkUpdated(existing.Id, request.systemModstamp); // No.20 排他チェック（変更モード、共通部品）
            }

            // ③ 受付番号の採番（(2)③ 受付番号の備考）
            // 追加モード、または登録済みの受付番号が 0・未設定の場合は、同じ従事事業の最大値＋1 で採番する
            // ※ 採番前に従事事業をロックしているため重複しない
            Decimal uketukeNo = null;
            if (isAdd || existing.Oubo_Uketuke_No__c == null || existing.Oubo_Uketuke_No__c == 0) {
                uketukeNo = selectMaxUketukeNo(jigyo.Id) + 1;
            }

            // ③ 従事事業応募の登録・更新
            Juji_Jigyo_Oubo__c rec;
            if (isAdd) {
                // (2)③ 追加モード：従事事業・会員または相談員を設定して新規作成
                rec = new Juji_Jigyo_Oubo__c(Oubo_Juji_Jigyo__c = jigyo.Id);
                if (jujisha.jujishaType == TYPE_MEMBER) {
                    rec.Oubo_Kaiin__c = jujisha.recordId;
                } else {
                    rec.Oubo_Soudanin_Master__c = jujisha.recordId;
                }
            } else {
                // (3)③ 変更モード：従事事業・会員・相談員は更新しない
                rec = new Juji_Jigyo_Oubo__c(Id = existing.Id);
            }
            if (uketukeNo != null) {
                rec.Oubo_Uketuke_No__c = uketukeNo;
            }
            // 氏名：取得した従事者の氏名（追加・変更とも設定する。画面表示・検索には使用しない）
            rec.Oubo_Shimei__c = String.isBlank(jujisha.name) ? null : jujisha.name.left(SHIMEI_LENGTH);
            applyForm(rec, request.form);
            if (isAdd) {
                Database.insert(rec, AccessLevel.USER_MODE);
            } else {
                Database.update(rec, AccessLevel.USER_MODE);
            }

            // ④ 従事事業応募明細の登録（従事可能日1日につき1件。選択した時間帯を JSON で設定する）
            // (3)④ 変更モード：既存の明細をすべて削除してから登録する
            if (!isAdd && !existing.Oubo_Meisa_Juji_Jigyo_Oubo__r.isEmpty()) {
                Database.delete(existing.Oubo_Meisa_Juji_Jigyo_Oubo__r, AccessLevel.USER_MODE);
            }
            List<Juji_Jigyo_Oubo_Meisai__c> details = new List<Juji_Jigyo_Oubo_Meisai__c>();
            if (request.kanoubiDates != null) {
                for (KanoubiDate kanoubi : request.kanoubiDates) {
                    // 時間帯が1件も選択されていない日付は登録しない
                    if (kanoubi.timeSlots == null || kanoubi.timeSlots.isEmpty()) {
                        continue;
                    }
                    details.add(
                        new Juji_Jigyo_Oubo_Meisai__c(
                            Oubo_Meisa_Juji_Jigyo_Oubo__c = rec.Id,
                            Oubo_Meisa_Juji_Jigyo__c = jigyo.Id,
                            Oubo_Meisa_Juji_Kano_Nengapi__c = Date.valueOf(kanoubi.kanoubiDate),
                            Oubo_Meisa_JisshiJikantai_Meisai__c = JSON.serialize(kanoubi.timeSlots)
                        )
                    );
                }
            }
            if (!details.isEmpty()) {
                Database.insert(details, AccessLevel.USER_MODE);
            }

            // 採番した場合のみ受付番号を返す（画面アクション No.12：最終受付番号に設定する）
            SaveResult result = new SaveResult();
            result.uketukeNo = uketukeNo;
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 画面アクション No.13 削除：5.データ更新 (4) ====================
    // systemModstamp：応募読込時のシステム更新日時（排他チェックに使用）
    @AuraEnabled
    public static void deleteApplication(
        String jujiJigyoNo,
        String jujiBasyoNo,
        String jisiNendo,
        String jujishaNo,
        Datetime systemModstamp
    ) {
        try {
            // ① 入力チェック（サーバ）
            // 従事事業をロックして取得する（No.16）。一括割当実行中の場合はエラー（No.15）
            Juji_Jigyo__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            checkBulkAssigning(jigyo.Id);
            // 従事者を取得する（No.17）
            JujishaInfo jujisha = findJujisha(jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }
            // 従事事業・従事者が一致する従事事業応募を取得する（No.21 削除対象データ未存在）
            Juji_Jigyo_Oubo__c app = selectApplicationByJujisha(jigyo.Id, jujisha);
            if (app == null) {
                throw error(E_APPLICATION_NOT_FOUND);
            }
            // No.20 排他チェック（共通部品）
            checkUpdated(app.Id, systemModstamp);
            // No.22 割当（仮割当を含む）が存在する場合はエラー
            if (hasAssignment(jigyo.Id, new List<Juji_Jigyo_Oubo__c>{ app })) {
                throw error(E_ASSIGNED);
            }
            // ② 削除する（従事事業応募明細は主従関係により同時に削除される）
            Database.delete(new Juji_Jigyo_Oubo__c(Id = app.Id), AccessLevel.USER_MODE);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 画面アクション No.14 全削除：5.データ更新 (5) ====================
    @AuraEnabled
    public static void deleteAllApplications(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        try {
            // ① 入力チェック（サーバ）
            // 従事事業をロックして取得する（No.16）。一括割当実行中の場合はエラー（No.15）
            Juji_Jigyo__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            checkBulkAssigning(jigyo.Id);
            // 従事事業の従事事業応募をすべて取得する。1件もない場合もエラーとしない（現行同様）
            List<Juji_Jigyo_Oubo__c> apps = [
                SELECT Id, Oubo_Kaiin__c, Oubo_Soudanin_Master__c
                FROM Juji_Jigyo_Oubo__c
                WHERE Oubo_Juji_Jigyo__c = :jigyo.Id
                WITH USER_MODE
            ];
            if (apps.isEmpty()) {
                return;
            }
            // No.22 1件でも割当が存在する場合はエラーとし、1件も削除しない
            if (hasAssignment(jigyo.Id, apps)) {
                throw error(E_ASSIGNED);
            }
            // ② すべて削除する（従事事業応募明細は主従関係により同時に削除される）
            Database.delete(apps, AccessLevel.USER_MODE);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== Selector ====================
    // 従事場所マスタ
    private static Juji_Basyo_Master__c selectBasyo(String basyoNo) {
        List<Juji_Basyo_Master__c> recs = [
            SELECT Id, JujM_Juji_Basyo_Name__c
            FROM Juji_Basyo_Master__c
            WHERE JujM_Juji_Basyo_No__c = :basyoNo
            WITH USER_MODE
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }

    // 従事事業（事業キーで取得。forUpdate＝true の場合はロックする）
    private static Juji_Jigyo__c selectJigyo(JigyoKey key, Boolean forUpdate) {
        // キーが揃っていない場合はクエリを発行しない
        if (key == null || !key.isComplete()) {
            return null;
        }
        String soql =
            'SELECT Id, Juji_Juji_Jigyo_Name__c, Juji_Jimusyo_Hojin__r.Jims_Sibu_Code__c, Juji_Jimusyo_Hojin__r.Jims_Sibu_Name__c,' +
            ' Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Yobi__c, Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Hi__c,' +
            ' Juji_Ouboji_Hisu_Nyuryoku_Flag_Kibo_Nisu__c, Juji_Ouboji_Hisu_Nyuryoku_Flag_5Dankai__c,' +
            ' Juji_Ouboji_Nini_Nyuryoku_Flag_5Dankai__c, Juji_Ouboji_Nini_Nyuryoku_Flag_Skill_Tok__c,' +
            ' Juji_Ouboji_Nini_Nyuryoku_Flag_Tyosyo__c, Juji_Ouboji_Nini_Nyuryoku_Flag_Sodan__c' +
            ' FROM Juji_Jigyo__c' +
            ' WHERE Juji_Juji_Jigyo_No__c = :jigyoNo' +
            ' AND Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_No__c = :basyoNo' +
            ' AND Juji_Jisi_Nendo__c = :nendo' +
            ' LIMIT 1' +
            (forUpdate ? ' FOR UPDATE' : '');
        Map<String, Object> binds = new Map<String, Object>{
            'jigyoNo' => key.jujiJigyoNo,
            'basyoNo' => key.jujiBasyoNo,
            'nendo' => key.jisiNendo
        };
        List<Juji_Jigyo__c> recs = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        return recs.isEmpty() ? null : recs[0];
    }

    // 受付番号の最大値（応募がない場合は 0）
    private static Decimal selectMaxUketukeNo(Id jigyoId) {
        List<AggregateResult> results = [
            SELECT MAX(Oubo_Uketuke_No__c) maxNo
            FROM Juji_Jigyo_Oubo__c
            WHERE Oubo_Juji_Jigyo__c = :jigyoId
            WITH USER_MODE
        ];
        Decimal maxNo = (Decimal) results[0].get('maxNo');
        return maxNo == null ? 0 : maxNo;
    }

    // 従事者の取得（画面アクション No.19：会員 → 相談員の順。取得できない場合は null）
    private static JujishaInfo findJujisha(String jujishaNo) {
        if (String.isBlank(jujishaNo)) {
            return null;
        }
        // a. 会員（Contact）から取得する
        //    氏名は標準項目 Name、フリガナは姓・名の2項目を連結する
        //    支部コード・支部名は会員が参照する事務所・法人（Account）、事務所住所・電話番号・FAX番号は会員から取得する
        List<Contact> members = [
            SELECT Id, Kaii_Toroku_No__c, Name, Kaii_Kaiin_Name_Furigana_Sei__c, Kaii_Kaiin_Name_Furigana_Mei__c,
                Account.Jims_Sibu_Code__c, Account.Jims_Sibu_Name__c,
                Kaii_Jimusyo_Syozaiti__c, Kaii_Jimusyo_Tel_No__c, Kaii_Jimusyo_Fax_No__c
            FROM Contact
            WHERE Kaii_Toroku_No__c = :jujishaNo
            WITH USER_MODE
            LIMIT 1
        ];
        if (!members.isEmpty()) {
            Contact m = members[0];
            JujishaInfo info = new JujishaInfo();
            info.jujishaType = TYPE_MEMBER;
            info.recordId = m.Id;
            info.jujishaNo = m.Kaii_Toroku_No__c;
            info.name = m.Name;
            info.furigana = joinName(m.Kaii_Kaiin_Name_Furigana_Sei__c, m.Kaii_Kaiin_Name_Furigana_Mei__c);
            info.shibuCode = m.Account?.Jims_Sibu_Code__c;
            info.shibuName = m.Account?.Jims_Sibu_Name__c;
            info.address = m.Kaii_Jimusyo_Syozaiti__c;
            info.tel = m.Kaii_Jimusyo_Tel_No__c;
            info.fax = m.Kaii_Jimusyo_Fax_No__c;
            return info;
        }
        // b. a で取得できない場合、相談員マスタから取得する（相談員の場合、支部コード・支部名は空白）
        List<Soudanin_Master__c> sodanins = [
            SELECT Id, SouM_Sodanin_No__c, SouM_Sodanin_Name__c, SouM_Sodanin_Name_Furigana__c,
                SouM_Jimusyo_Jusyo__c, SouM_Jimusyo_Tel_No__c, SouM_Jimusyo_Fax_No__c
            FROM Soudanin_Master__c
            WHERE SouM_Sodanin_No__c = :jujishaNo
            WITH USER_MODE
            LIMIT 1
        ];
        if (!sodanins.isEmpty()) {
            Soudanin_Master__c s = sodanins[0];
            JujishaInfo info = new JujishaInfo();
            info.jujishaType = TYPE_SODANIN;
            info.recordId = s.Id;
            info.jujishaNo = s.SouM_Sodanin_No__c;
            info.name = s.SouM_Sodanin_Name__c;
            info.furigana = s.SouM_Sodanin_Name_Furigana__c;
            info.address = s.SouM_Jimusyo_Jusyo__c;
            info.tel = s.SouM_Jimusyo_Tel_No__c;
            info.fax = s.SouM_Jimusyo_Fax_No__c;
            return info;
        }
        return null;
    }

    // 従事事業応募（応募IDで取得）
    private static Juji_Jigyo_Oubo__c selectApplicationById(Id applicationId) {
        if (applicationId == null) {
            return null;
        }
        List<Juji_Jigyo_Oubo__c> recs = Database.queryWithBinds(
            applicationSoql('Id = :applicationId'),
            new Map<String, Object>{ 'applicationId' => applicationId },
            AccessLevel.USER_MODE
        );
        return recs.isEmpty() ? null : recs[0];
    }

    // 従事事業応募（事業＋従事者で取得）
    private static Juji_Jigyo_Oubo__c selectApplicationByJujisha(Id jigyoId, JujishaInfo jujisha) {
        // 応募は会員・相談員のどちらか一方のみ設定されるため、もう一方は null（IS NULL）で検索する
        Map<String, Object> binds = new Map<String, Object>{
            'jigyoId' => jigyoId,
            'memberId' => jujisha.jujishaType == TYPE_MEMBER ? jujisha.recordId : null,
            'sodaninId' => jujisha.jujishaType == TYPE_SODANIN ? jujisha.recordId : null
        };
        List<Juji_Jigyo_Oubo__c> recs = Database.queryWithBinds(
            applicationSoql(
                'Oubo_Juji_Jigyo__c = :jigyoId AND Oubo_Kaiin__c = :memberId AND Oubo_Soudanin_Master__c = :sodaninId'
            ),
            binds,
            AccessLevel.USER_MODE
        );
        return recs.isEmpty() ? null : recs[0];
    }

    // 5.データ更新 (1) 従事事業応募の取得 SOQL（① 従事事業応募、② 従事事業応募明細（従事可能日の昇順）を含む）
    private static String applicationSoql(String whereClause) {
        List<String> fields = new List<String>{
            'Id',
            'Oubo_Uketuke_No__c',
            'SystemModstamp',
            'Oubo_Kaiin__c',
            'Oubo_Kaiin__r.Kaii_Toroku_No__c',
            'Oubo_Soudanin_Master__c',
            'Oubo_Soudanin_Master__r.SouM_Sodanin_No__c',
            'Oubo_Juji_Jigyo__r.Juji_Juji_Jigyo_No__c',
            'Oubo_Juji_Jigyo__r.Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_No__c',
            'Oubo_Juji_Jigyo__r.Juji_Jisi_Nendo__c',
            'Oubo_Renrakusaki_Kotei_No__c',
            'Oubo_Renrakusaki_Tel_No__c',
            'Oubo_Renrakusaki_Fax_No__c',
            'Oubo_Renrakusaki_Mail__c',
            'Oubo_Biko__c',
            'Oubo_Kibo_Juji_Nisu__c',
            'Oubo_Juji_Keiken__c',
            'Oubo_Skill_Toki_Jiko__c',
            'Oubo_Tyosyo_Ronbun__c',
            'Oubo_Sodan_Kamoku__c'
        };
        fields.addAll(WEEKDAY_FIELDS.values());
        fields.addAll(SKILL_FIELDS);
        return 'SELECT ' + String.join(fields, ', ') +
            ', (SELECT Id, Oubo_Meisa_Juji_Kano_Nengapi__c, Oubo_Meisa_JisshiJikantai_Meisai__c' +
            ' FROM Oubo_Meisa_Juji_Jigyo_Oubo__r ORDER BY Oubo_Meisa_Juji_Kano_Nengapi__c)' +
            ' FROM Juji_Jigyo_Oubo__c' +
            ' WHERE ' + whereClause +
            ' LIMIT 1';
    }

    // ==================== 変換 ====================
    // 従事事業キー（3項目）
    private static JigyoKey toKey(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        JigyoKey key = new JigyoKey();
        key.jujiJigyoNo = jujiJigyoNo;
        key.jujiBasyoNo = jujiBasyoNo;
        key.jisiNendo = jisiNendo;
        return key;
    }

    // 姓・名を半角スペースで連結する（いずれかが空の場合は空でない方のみ）
    @TestVisible
    private static String joinName(String sei, String mei) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(sei)) {
            parts.add(sei);
        }
        if (String.isNotBlank(mei)) {
            parts.add(mei);
        }
        return String.join(parts, ' ');
    }

    // 内部クラス → 画面へ返す Map（JSON 経由で変換。transient の項目は含まれない）
    @TestVisible
    private static Map<String, Object> toMap(Object dto) {
        if (dto == null) {
            return null;
        }
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dto));
    }

    // 実施時間帯明細（JSON）→ 時間帯リスト（未設定・形式不正の場合は空。使用しない項目は無視する）
    @TestVisible
    private static List<TimeSlot> parseTimeSlots(String value) {
        if (String.isBlank(value)) {
            return new List<TimeSlot>();
        }
        try {
            return (List<TimeSlot>) JSON.deserialize(value, List<TimeSlot>.class);
        } catch (JSONException e) {
            return new List<TimeSlot>();
        }
    }

    // 従事事業 → 画面表示用（画面アクション No.18）
    private static JigyoInfo toJigyoInfo(Juji_Jigyo__c jigyo) {
        JigyoInfo info = new JigyoInfo();
        info.jigyoName = jigyo.Juji_Juji_Jigyo_Name__c;
        // 支部コード・支部名：従事事業が参照する事務所・法人
        info.shibuCode = jigyo.Juji_Jimusyo_Hojin__r?.Jims_Sibu_Code__c;
        info.shibuName = jigyo.Juji_Jimusyo_Hojin__r?.Jims_Sibu_Name__c;
        // 最終受付番号：受付番号の最大値（0 または応募なしの場合は空白）
        Decimal maxNo = selectMaxUketukeNo(jigyo.Id);
        info.lastUketukeNo = maxNo == 0 ? null : maxNo;
        info.inputControl = getInputControl(jigyo);
        return info;
    }

    // 従事事業応募 → 画面表示用（画面アクション No.20 応募情報読込、5.データ更新 (1) の設定先）
    private static ApplicationInfo toApplicationInfo(Juji_Jigyo_Oubo__c app) {
        ApplicationForm form = new ApplicationForm();
        form.telFixed = app.Oubo_Renrakusaki_Kotei_No__c;
        form.telMobile = app.Oubo_Renrakusaki_Tel_No__c;
        form.fax = app.Oubo_Renrakusaki_Fax_No__c;
        form.mail = app.Oubo_Renrakusaki_Mail__c;
        form.biko = app.Oubo_Biko__c;
        // 【要確認 QA-17④】全日程従事可能は専用項目を持たない（登録時に全曜日を「可」とする）ため、読込時は OFF とする
        form.allDays = false;
        form.weekdays = new List<String>();
        for (String day : WEEKDAYS) {
            if (app.get(WEEKDAY_FIELDS.get(day)) == WEEKDAY_KA) {
                form.weekdays.add(day);
            }
        }
        form.kibouNissu = app.Oubo_Kibo_Juji_Nisu__c == null ? null : String.valueOf(app.Oubo_Kibo_Juji_Nisu__c);
        form.keiken = app.Oubo_Juji_Keiken__c; // 有／無
        form.skills = new List<SkillValue>();
        for (String field : SKILL_FIELDS) {
            String value = (String) app.get(field);
            if (String.isNotBlank(value)) {
                SkillValue skill = new SkillValue();
                skill.field = field;
                skill.value = value;
                form.skills.add(skill);
            }
        }
        form.skillNote = app.Oubo_Skill_Toki_Jiko__c;
        form.chosho = app.Oubo_Tyosyo_Ronbun__c;
        form.sodanKamoku = app.Oubo_Sodan_Kamoku__c;

        ApplicationInfo info = new ApplicationInfo();
        info.applicationId = app.Id;
        info.uketukeNo = app.Oubo_Uketuke_No__c;
        info.systemModstamp = app.SystemModstamp; // 4.入力チェック No.20 の排他チェックに使用
        info.form = form;
        info.kanoubiDates = new List<KanoubiDate>();
        for (Juji_Jigyo_Oubo_Meisai__c detail : app.Oubo_Meisa_Juji_Jigyo_Oubo__r) {
            KanoubiDate kanoubi = new KanoubiDate();
            kanoubi.kanoubiDate = String.valueOf(detail.Oubo_Meisa_Juji_Kano_Nengapi__c); // 'yyyy-MM-dd'
            kanoubi.timeSlots = parseTimeSlots(detail.Oubo_Meisa_JisshiJikantai_Meisai__c);
            info.kanoubiDates.add(kanoubi);
        }
        return info;
    }

    // 画面の入力値 → 従事事業応募（5.データ更新 (2)③ の設定値）
    private static void applyForm(Juji_Jigyo_Oubo__c rec, ApplicationForm form) {
        if (form == null) {
            form = new ApplicationForm();
        }
        rec.Oubo_Renrakusaki_Kotei_No__c = form.telFixed;
        rec.Oubo_Renrakusaki_Tel_No__c = form.telMobile;
        rec.Oubo_Renrakusaki_Fax_No__c = form.fax;
        rec.Oubo_Renrakusaki_Mail__c = form.mail;
        rec.Oubo_Biko__c = form.biko;
        // 従事可能曜日：選択＝「可」、未選択＝「不可」。全日程従事可能が ON の場合はすべて「可」とする
        Set<String> weekdays = form.weekdays == null ? new Set<String>() : new Set<String>(form.weekdays);
        for (String day : WEEKDAYS) {
            Boolean isKa = form.allDays == true || weekdays.contains(day);
            rec.put(WEEKDAY_FIELDS.get(day), isKa ? WEEKDAY_KA : WEEKDAY_FUKA);
        }
        rec.Oubo_Kibo_Juji_Nisu__c = String.isBlank(form.kibouNissu) ? null : Decimal.valueOf(form.kibouNissu);
        rec.Oubo_Juji_Keiken__c = form.keiken;
        // スキル：画面から受け取った項目名が SKILL_FIELDS に含まれるもののみ設定し、値が選択されていない科目は空とする
        Map<String, String> skillValues = new Map<String, String>();
        if (form.skills != null) {
            for (SkillValue skill : form.skills) {
                skillValues.put(skill.field, skill.value);
            }
        }
        for (String field : SKILL_FIELDS) {
            String value = skillValues.get(field);
            rec.put(field, String.isBlank(value) ? null : value);
        }
        rec.Oubo_Skill_Toki_Jiko__c = form.skillNote;
        rec.Oubo_Tyosyo_Ronbun__c = form.chosho;
        rec.Oubo_Sodan_Kamoku__c = form.sodanKamoku;
    }

    // ==================== 事業設定による入力制御（3.表示ラベル No.28〜37 の備考）====================
    // 事業の必須入力フラグ（必須／省略可）・任意入力フラグ（許可／禁止）を画面の入力制御に変換する
    // ※ 未設定（空白）の場合は制限しない（必須入力フラグは「省略可」、任意入力フラグは「許可」として扱う）
    private static InputControl getInputControl(Juji_Jigyo__c jigyo) {
        InputControl ctrl = new InputControl();
        // 必須入力フラグ：「必須」の場合のみ true
        ctrl.requiredWeekday = jigyo.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Yobi__c == REQUIRED_ON;
        ctrl.requiredKanoubi = jigyo.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Hi__c == REQUIRED_ON;
        ctrl.requiredKibouNissu = jigyo.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kibo_Nisu__c == REQUIRED_ON;
        ctrl.requiredSkill = jigyo.Juji_Ouboji_Hisu_Nyuryoku_Flag_5Dankai__c == REQUIRED_ON;
        // 任意入力フラグ：「禁止」以外（許可・空白）の場合は true
        ctrl.optionalSkill = jigyo.Juji_Ouboji_Nini_Nyuryoku_Flag_5Dankai__c != OPTIONAL_OFF;
        ctrl.optionalSkillNote = jigyo.Juji_Ouboji_Nini_Nyuryoku_Flag_Skill_Tok__c != OPTIONAL_OFF;
        ctrl.optionalChosho = jigyo.Juji_Ouboji_Nini_Nyuryoku_Flag_Tyosyo__c != OPTIONAL_OFF;
        ctrl.optionalSodanKamoku = jigyo.Juji_Ouboji_Nini_Nyuryoku_Flag_Sodan__c != OPTIONAL_OFF;
        return ctrl;
    }

    // 実施日（従事事業明細）が1件以上あるか（4.入力チェック No.14）
    private static Boolean hasJisshibi(Id jigyoId) {
        return [SELECT COUNT() FROM Juji_Jigyo_Meisai__c WHERE Juji_Meisai_Juji_Jigyo__c = :jigyoId WITH USER_MODE] > 0;
    }

    // ==================== 共通チェック（Juj_CommonController） ====================
    // 4.入力チェック No.15 一括割当実行中の場合はエラー（共通側で AuraHandledException を発生させる）
    private static void checkBulkAssigning(Id jigyoId) {
        Juj_CommonController.checkIkkatsuExecution(jigyoId, NO_CHECK_KEYS);
    }

    // 4.入力チェック No.20 応募読込時から他のユーザにより更新されている場合はエラー（共通側で AuraHandledException を発生させる）
    // ※ 削除済みは検出されないため、呼出し前に応募の存在を確認すること（No.19・No.21）
    private static void checkUpdated(Id applicationId, Datetime systemModstamp) {
        Juj_CommonController.checkOptimisticLock(new Map<Id, Datetime>{ applicationId => systemModstamp }, OBO_OBJECT_NAME);
    }

    // 4.入力チェック No.22 応募の従事者に、同じ事業の割当（仮割当を含む）が存在するか
    // ※ 割当は従事事業の主従子オブジェクトで、会員・相談員を参照する（応募への参照はない）
    //   仮割当＝割当フラグ＝1、確定＝確定フラグ＝1
    private static Boolean hasAssignment(Id jigyoId, List<Juji_Jigyo_Oubo__c> apps) {
        Set<Id> memberIds = new Set<Id>();
        Set<Id> sodaninIds = new Set<Id>();
        for (Juji_Jigyo_Oubo__c app : apps) {
            if (app.Oubo_Kaiin__c != null) {
                memberIds.add(app.Oubo_Kaiin__c);
            }
            if (app.Oubo_Soudanin_Master__c != null) {
                sodaninIds.add(app.Oubo_Soudanin_Master__c);
            }
        }
        if (memberIds.isEmpty() && sodaninIds.isEmpty()) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM Juji_Jigyo_Wariate__c
            WHERE Wari_Juji_Jigyo__c = :jigyoId
            AND (Wari_Wriate_Flag__c = :FLAG_ON OR Wari_Kakutei_Flag__c = :FLAG_ON)
            AND (Wari_Kaiin__c IN :memberIds OR Wari_Soudanin_Master__c IN :sodaninIds)
            WITH USER_MODE
        ] > 0;
    }

    // ==================== 例外 ====================
    // 業務エラー（メッセージID 付き）
    public class JujiOboException extends Exception {
        public String messageId;
    }

    private static JujiOboException error(List<String> msg) {
        JujiOboException e = new JujiOboException(msg[1]);
        e.messageId = msg[0];
        return e;
    }

    // 画面へ返す例外に変換する（setMessage しないと画面に文言が渡らない）
    private static AuraHandledException toAuraException(JujiOboException e) {
        AuraHandledException ae = new AuraHandledException(e.getMessage());
        ae.setMessage(e.getMessage());
        return ae;
    }

    // ==================== DTO（クラス内部でのみ使用。画面との受渡しは JSON・Map 経由） ====================
    // 従事事業キー
    public class JigyoKey {
        public String jujiJigyoNo;
        public String jujiBasyoNo;
        public String jisiNendo;

        // 3項目すべて入力されているか
        public Boolean isComplete() {
            return String.isNotBlank(jujiJigyoNo) && String.isNotBlank(jujiBasyoNo) && String.isNotBlank(jisiNendo);
        }
    }

    public class JigyoResult {
        public String basyoName;
        public JigyoInfo jigyo;
    }

    public class JigyoInfo {
        public String jigyoName;
        public String shibuCode;
        public String shibuName;
        public Decimal lastUketukeNo;
        public InputControl inputControl;
    }

    // 事業設定による入力制御
    public class InputControl {
        public Boolean requiredWeekday;
        public Boolean requiredKanoubi;
        public Boolean requiredKibouNissu;
        public Boolean requiredSkill;
        public Boolean optionalSkill;
        public Boolean optionalSkillNote;
        public Boolean optionalChosho;
        public Boolean optionalSodanKamoku;
    }

    // 従事者情報部
    public class JujishaInfo {
        public String jujishaType;
        public String jujishaNo;
        public String name;
        public String furigana;
        public String shibuCode;
        public String shibuName;
        public String address;
        public String tel;
        public String fax;
        // 会員ID または相談員ID（サーバ内部でのみ使用。transient のため画面には返さない）
        public transient Id recordId;
    }

    // 応募情報の読込結果
    public class LoadApplicationResult {
        public JigyoKey jigyoKey;
        public String jujishaNo;
        public JujishaInfo jujisha;
        public ApplicationInfo application;
    }

    // 応募情報（受付番号・応募情報部・従事可能日）
    public class ApplicationInfo {
        public Id applicationId;
        public Decimal uketukeNo;
        public Datetime systemModstamp;
        public ApplicationForm form;
        public List<KanoubiDate> kanoubiDates;
    }

    // 従事可能日（日付と選択した時間帯）
    public class KanoubiDate {
        public String kanoubiDate; // 'yyyy-MM-dd'
        public List<TimeSlot> timeSlots;
    }

    // 時間帯（応募明細の実施時間帯明細に JSON で保持する。開始時間＋終了時間で同一判定する）
    public class TimeSlot {
        public String startTime; // 'HH:mm'
        public String endTime; // 'HH:mm'
    }

    // 応募情報部
    public class ApplicationForm {
        public String telFixed;
        public String telMobile;
        public String fax;
        public String mail;
        public String biko;
        public Boolean allDays;
        public List<String> weekdays;
        public String kibouNissu;
        public String keiken; // 有／無
        public List<SkillValue> skills;
        public String skillNote;
        public String chosho;
        public String sodanKamoku;
    }

    // スキル（項目名・選択値）
    public class SkillValue {
        public String field;
        public String value;
    }

    // 登録リクエスト
    public class SaveRequest {
        public JigyoKey jigyoKey;
        public String jujishaNo;
        public Id applicationId;
        public Datetime systemModstamp;
        public ApplicationForm form;
        public List<KanoubiDate> kanoubiDates;
    }

    public class SaveResult {
        public Decimal uketukeNo;
    }
}
